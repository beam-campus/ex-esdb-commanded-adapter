defmodule ExESDB.Commanded.AggregateListenerSupervisor do
  @moduledoc """
  DynamicSupervisor for managing AggregateListener processes.
  
  This supervisor is responsible for:
  1. Starting and stopping AggregateListener processes
  2. Ensuring proper supervision and restart strategies
  3. Maintaining a registry of active listeners
  4. Cleanup on application shutdown
  """
  
  use DynamicSupervisor
  require Logger
  
  alias ExESDB.Commanded.AggregateListener
  
  @registry_name __MODULE__.Registry
  
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl DynamicSupervisor
  def init(_opts) do
    # Start the registry for tracking listeners
    Registry.start_link(keys: :unique, name: @registry_name)
    
    Logger.info("AggregateListenerSupervisor: Started")
    
    DynamicSupervisor.init(
      strategy: :one_for_one,
      restart: :temporary  # Don't restart listeners automatically - let the adapter handle it
    )
  end
  
  @doc """
  Starts a new AggregateListener under supervision.
  
  Returns the PID of the started listener or an error.
  """
  @spec start_listener(map()) :: {:ok, pid()} | {:error, term()}
  def start_listener(config) do
    store_id = Map.fetch!(config, :store_id)
    stream_id = Map.fetch!(config, :stream_id)
    subscriber = Map.fetch!(config, :subscriber)
    
    # Create a unique key for this listener
    listener_key = {store_id, stream_id, subscriber}
    
    # Check if a listener already exists for this combination
    case Registry.lookup(@registry_name, listener_key) do
      [{existing_pid, _}] when is_pid(existing_pid) ->
        # Check if the process is still alive
        if Process.alive?(existing_pid) do
          Logger.debug(
            "AggregateListenerSupervisor: Reusing existing listener for stream '#{stream_id}'"
          )
          {:ok, existing_pid}
        else
          # Clean up dead process and start a new one
          Registry.unregister(@registry_name, listener_key)
          do_start_listener(config, listener_key)
        end
      
      [] ->
        # No existing listener, start a new one
        do_start_listener(config, listener_key)
    end
  end
  
  @doc """
  Stops a specific AggregateListener.
  """
  @spec stop_listener(pid()) :: :ok
  def stop_listener(pid) when is_pid(pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok -> 
        Logger.debug("AggregateListenerSupervisor: Stopped listener #{inspect(pid)}")
        :ok
      {:error, :not_found} -> 
        Logger.debug("AggregateListenerSupervisor: Listener #{inspect(pid)} not found")
        :ok
      {:error, reason} -> 
        Logger.warning("AggregateListenerSupervisor: Failed to stop listener #{inspect(pid)}: #{inspect(reason)}")
        :ok
    end
  end
  
  @doc """
  Stops all listeners for a specific store and stream combination.
  """
  @spec stop_listeners_for_stream(atom(), String.t()) :: :ok
  def stop_listeners_for_stream(store_id, stream_id) do
    # Find all listeners for this store/stream combination
    @registry_name
    |> Registry.select([
      {{:"$1", :"$2", :"$3"}, 
       [
         {:andalso, 
          {:==, {:element, 1, :"$1"}, store_id},
          {:==, {:element, 2, :"$1"}, stream_id}
         }
       ], 
       [:"$2"]}
    ])
    |> Enum.each(&stop_listener/1)
  end
  
  @doc """
  Returns statistics about active listeners.
  """
  @spec stats() :: %{
    total_listeners: non_neg_integer(),
    listeners_by_store: %{atom() => non_neg_integer()},
    active_streams: [String.t()]
  }
  def stats do
    listeners = Registry.select(@registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    
    listeners_by_store = 
      listeners
      |> Enum.map(fn {store_id, _stream_id, _subscriber} -> store_id end)
      |> Enum.frequencies()
    
    active_streams = 
      listeners
      |> Enum.map(fn {_store_id, stream_id, _subscriber} -> stream_id end)
      |> Enum.uniq()
    
    %{
      total_listeners: length(listeners),
      listeners_by_store: listeners_by_store,
      active_streams: active_streams
    }
  end
  
  @doc """
  Lists all active listeners with their details.
  """
  @spec list_listeners() :: [%{store_id: atom(), stream_id: String.t(), subscriber: pid(), listener_pid: pid()}]
  def list_listeners do
    Registry.select(@registry_name, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.map(fn {{store_id, stream_id, subscriber}, listener_pid} ->
      %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: subscriber,
        listener_pid: listener_pid
      }
    end)
  end
  
  # Private functions
  
  defp do_start_listener(config, listener_key) do
    child_spec = {AggregateListener, config}
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        # Register the listener in our registry
        case Registry.register(@registry_name, listener_key, nil) do
          {:ok, _} ->
            Logger.info(
              "AggregateListenerSupervisor: Started listener #{inspect(pid)} for stream '#{config.stream_id}'"
            )
            {:ok, pid}
          
          {:error, {:already_registered, existing_pid}} ->
            # Race condition - another process started a listener
            DynamicSupervisor.terminate_child(__MODULE__, pid)
            {:ok, existing_pid}
        end
      
      {:error, reason} ->
        Logger.error(
          "AggregateListenerSupervisor: Failed to start listener for stream '#{config.stream_id}': #{inspect(reason)}"
        )
        {:error, reason}
    end
  end
end
