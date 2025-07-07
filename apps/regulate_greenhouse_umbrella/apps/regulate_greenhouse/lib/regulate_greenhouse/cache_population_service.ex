defmodule RegulateGreenhouse.CachePopulationService do
  @moduledoc """
  Service responsible for populating the cache on application startup.
  
  This service:
  - Waits for ExESDB connectivity
  - Rebuilds cache from event streams
  - Retries on failures with exponential backoff
  - Integrates with the supervision tree
  - Provides detailed logging and monitoring
  """
  
  use GenServer
  require Logger
  
  alias RegulateGreenhouse.CacheRebuildService
  alias ExESDBGater.API
  
  @store_id :reg_gh
  @max_retries 10
  @initial_delay_ms 1_000
  @max_delay_ms 30_000
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end
  
  @doc """
  Check if cache population has completed successfully.
  """
  def population_status do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> GenServer.call(pid, :get_status)
    end
  end
  
  @doc """
  Manually trigger cache population (useful for testing or manual recovery).
  """
  def populate_cache do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> GenServer.call(pid, :populate_cache, 60_000)
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, Application.get_env(:regulate_greenhouse, :populate_cache_on_startup, true))
    
    if enabled do
      Logger.info("CachePopulationService: Starting cache population service")
      # Start population process after a short delay to allow other services to start
      Process.send_after(self(), :start_population, 2_000)
    else
      Logger.info("CachePopulationService: Cache population disabled")
    end
    
    state = %{
      enabled: enabled,
      status: :waiting,
      retry_count: 0,
      last_error: nil,
      population_stats: nil,
      population_task: nil,
      started_at: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_info(:start_population, %{enabled: false} = state) do
    {:noreply, state}
  end
  
  def handle_info(:start_population, state) do
    Logger.info("CachePopulationService: Starting cache population process")
    new_state = %{state | status: :populating}
    
    # Start population in a separate process to avoid blocking the GenServer
    task = Task.async(fn -> perform_cache_population() end)
    
    {:noreply, %{new_state | population_task: task}}
  end
  
  def handle_info({ref, result}, %{population_task: %Task{ref: ref}} = state) when not is_nil(ref) do
    # Population task completed
    Process.demonitor(ref, [:flush])
    
    case result do
      {:ok, stats} ->
        Logger.info("CachePopulationService: Cache population completed successfully")
        Logger.info("CachePopulationService: Population stats: #{inspect(stats)}")
        
        new_state = %{state | 
          status: :completed,
          population_stats: stats,
          population_task: nil
        }
        
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.error("CachePopulationService: Cache population failed: #{inspect(reason)}")
        
        new_state = %{state | 
          status: :failed,
          last_error: reason,
          retry_count: state.retry_count + 1,
          population_task: nil
        }
        
        # Schedule retry if we haven't exceeded max retries
        if new_state.retry_count < @max_retries do
          delay = calculate_retry_delay(new_state.retry_count)
          Logger.info("CachePopulationService: Scheduling retry #{new_state.retry_count}/#{@max_retries} in #{delay}ms")
          Process.send_after(self(), :start_population, delay)
          {:noreply, %{new_state | status: :retrying}}
        else
          Logger.error("CachePopulationService: Max retries exceeded, giving up")
          {:noreply, new_state}
        end
    end
  end
  
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{population_task: %Task{ref: ref}} = state) when not is_nil(ref) do
    # Population task crashed
    Logger.error("CachePopulationService: Population task crashed: #{inspect(reason)}")
    
    new_state = %{state | 
      status: :failed,
      last_error: {:task_crashed, reason},
      retry_count: state.retry_count + 1,
      population_task: nil
    }
    
    # Schedule retry if we haven't exceeded max retries
    if new_state.retry_count < @max_retries do
      delay = calculate_retry_delay(new_state.retry_count)
      Logger.info("CachePopulationService: Scheduling retry #{new_state.retry_count}/#{@max_retries} in #{delay}ms")
      Process.send_after(self(), :start_population, delay)
      {:noreply, %{new_state | status: :retrying}}
    else
      Logger.error("CachePopulationService: Max retries exceeded after task crash, giving up")
      {:noreply, new_state}
    end
  end
  
  # Handle unexpected task completion messages when no task is running
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Logger.debug("CachePopulationService: Received task completion message when no task expected: #{inspect(ref)}")
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end
  
  # Handle unexpected DOWN messages when no task is running
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) when is_reference(ref) do
    Logger.debug("CachePopulationService: Received DOWN message when no task expected: #{inspect(ref)}")
    {:noreply, state}
  end
  
  def handle_info(msg, state) do
    Logger.debug("CachePopulationService: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      retry_count: state.retry_count,
      last_error: state.last_error,
      population_stats: state.population_stats,
      started_at: state.started_at,
      enabled: state.enabled
    }
    
    {:reply, {:ok, status_info}, state}
  end
  
  def handle_call(:populate_cache, _from, %{enabled: false} = state) do
    {:reply, {:error, :disabled}, state}
  end
  
  def handle_call(:populate_cache, _from, %{status: :populating} = state) do
    {:reply, {:error, :already_running}, state}
  end
  
  def handle_call(:populate_cache, _from, state) do
    Logger.info("CachePopulationService: Manual cache population requested")
    
    # Start population
    task = Task.async(fn -> perform_cache_population() end)
    new_state = %{state | 
      status: :populating,
      retry_count: 0,
      last_error: nil,
      population_task: task
    }
    
    {:reply, :ok, new_state}
  end
  
  # Private functions
  
  defp perform_cache_population do
    Logger.info("CachePopulationService: Checking ExESDB connectivity...")
    
    # Step 1: Wait for ExESDB connectivity
    case wait_for_esdb_connectivity() do
      :ok ->
        Logger.info("CachePopulationService: ExESDB connectivity confirmed")
        
        # Step 2: Check if cache needs population
        case check_cache_status() do
          {:needs_population, stream_count} ->
            Logger.info("CachePopulationService: Cache needs population (#{stream_count} streams found)")
            
            # Step 3: Perform cache rebuild
            case CacheRebuildService.rebuild_cache() do
              {:ok, stats} ->
                Logger.info("CachePopulationService: Cache population successful")
                {:ok, stats}
                
              {:error, reason} ->
                Logger.error("CachePopulationService: Cache rebuild failed: #{inspect(reason)}")
                {:error, {:rebuild_failed, reason}}
            end
            
          {:no_population_needed, cache_size} ->
            Logger.info("CachePopulationService: Cache already populated (#{cache_size} items)")
            {:ok, %{
              cache_already_populated: true,
              cache_size: cache_size,
              duration_ms: 0,
              events_processed: 0,
              streams_processed: 0
            }}
            
          {:error, reason} ->
            Logger.error("CachePopulationService: Failed to check cache status: #{inspect(reason)}")
            {:error, {:cache_check_failed, reason}}
        end
        
      {:error, reason} ->
        Logger.error("CachePopulationService: ExESDB connectivity check failed: #{inspect(reason)}")
        {:error, {:connectivity_failed, reason}}
    end
  end
  
  defp wait_for_esdb_connectivity(attempt \\ 1, max_attempts \\ 30) do
    Logger.debug("CachePopulationService: Checking ExESDB connectivity (attempt #{attempt}/#{max_attempts})")
    
    case API.get_streams(@store_id) do
      {:ok, _streams} ->
        Logger.info("CachePopulationService: ExESDB connectivity confirmed on attempt #{attempt}")
        :ok
        
      {:error, reason} when attempt < max_attempts ->
        Logger.debug("CachePopulationService: ExESDB not ready (attempt #{attempt}): #{inspect(reason)}")
        :timer.sleep(1_000)
        wait_for_esdb_connectivity(attempt + 1, max_attempts)
        
      {:error, reason} ->
        Logger.error("CachePopulationService: ExESDB connectivity failed after #{max_attempts} attempts: #{inspect(reason)}")
        {:error, {:max_connectivity_attempts, reason}}
    end
  end
  
  defp check_cache_status do
    try do
      # Check current cache size
      case RegulateGreenhouse.CacheService.count_greenhouses() do
        cache_size when cache_size > 0 ->
          # Cache has items, check if it seems complete by comparing with streams
          case API.get_streams(@store_id) do
            {:ok, streams} ->
              stream_count = length(streams)
              
              # If cache size is roughly similar to stream count, assume cache is populated
              # (allowing for some variance since not all streams might be greenhouse streams)
              if cache_size >= stream_count * 0.8 do
                {:no_population_needed, cache_size}
              else
                Logger.info("CachePopulationService: Cache partially populated (#{cache_size} items vs #{stream_count} streams)")
                {:needs_population, stream_count}
              end
              
            {:error, reason} ->
              {:error, {:get_streams_failed, reason}}
          end
          
        0 ->
          # Cache is empty, check if there are streams to populate from
          case API.get_streams(@store_id) do
            {:ok, streams} ->
              stream_count = length(streams)
              
              if stream_count > 0 do
                {:needs_population, stream_count}
              else
                Logger.info("CachePopulationService: No streams found, no population needed")
                {:no_population_needed, 0}
              end
              
            {:error, reason} ->
              {:error, {:get_streams_failed, reason}}
          end
      end
    rescue
      e ->
        {:error, {:cache_check_exception, e}}
    end
  end
  
  defp calculate_retry_delay(retry_count) do
    # Exponential backoff with jitter
    base_delay = min(@initial_delay_ms * :math.pow(2, retry_count), @max_delay_ms)
    jitter = :rand.uniform(1000)  # Add up to 1 second of jitter
    round(base_delay + jitter)
  end
end
