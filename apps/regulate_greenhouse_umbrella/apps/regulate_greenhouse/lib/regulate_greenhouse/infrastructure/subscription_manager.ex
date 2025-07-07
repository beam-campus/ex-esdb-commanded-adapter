defmodule RegulateGreenhouse.Infrastructure.SubscriptionManager do
  @moduledoc """
  Subscription manager for monitoring and automatically restarting failed subscriptions.
  
  This module monitors subscription health and restarts them when they fail,
  providing resilience against network issues, process crashes, and cluster events.
  """
  
  use GenServer
  require Logger
  
  alias RegulateGreenhouse.Projections.GreenhouseProjection
  
  defstruct [
    :subscriptions,
    :monitor_interval,
    :restart_attempts,
    :max_restart_attempts
  ]
  
  @default_monitor_interval :timer.seconds(30)
  @default_max_restart_attempts 5
  @restart_backoff_base 1000  # Start with 1 second
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Register a subscription for monitoring.
  """
  def register_subscription(subscription_name, subscription_pid, restart_fun) do
    GenServer.call(__MODULE__, {:register, subscription_name, subscription_pid, restart_fun})
  end
  
  @doc """
  Unregister a subscription from monitoring.
  """
  def unregister_subscription(subscription_name) do
    GenServer.call(__MODULE__, {:unregister, subscription_name})
  end
  
  @doc """
  Get status of all monitored subscriptions.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Force restart a specific subscription.
  """
  def restart_subscription(subscription_name) do
    GenServer.call(__MODULE__, {:restart, subscription_name})
  end
  
  @doc """
  Check if a subscription is healthy.
  """
  def is_healthy?(subscription_name) do
    GenServer.call(__MODULE__, {:health_check, subscription_name})
  end
  
  # Server Implementation
  
  @impl GenServer
  def init(opts) do
    monitor_interval = Keyword.get(opts, :monitor_interval, @default_monitor_interval)
    max_restart_attempts = Keyword.get(opts, :max_restart_attempts, @default_max_restart_attempts)
    
    state = %__MODULE__{
      subscriptions: %{},
      monitor_interval: monitor_interval,
      restart_attempts: %{},
      max_restart_attempts: max_restart_attempts
    }
    
    # Schedule the first health check
    Process.send_after(self(), :health_check, monitor_interval)
    
    Logger.info("SubscriptionManager started with monitor interval #{monitor_interval}ms")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:register, name, pid, restart_fun}, _from, state) do
    # Monitor the subscription process
    ref = Process.monitor(pid)
    
    subscription = %{
      name: name,
      pid: pid,
      monitor_ref: ref,
      restart_fun: restart_fun,
      status: :healthy,
      last_check: System.monotonic_time(:millisecond),
      registered_at: DateTime.utc_now()
    }
    
    new_subscriptions = Map.put(state.subscriptions, name, subscription)
    new_state = %{state | subscriptions: new_subscriptions}
    
    Logger.info("SubscriptionManager: Registered subscription #{name} with PID #{inspect(pid)}")
    {:reply, :ok, new_state}
  end
  
  def handle_call({:unregister, name}, _from, state) do
    case Map.get(state.subscriptions, name) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      subscription ->
        # Stop monitoring
        Process.demonitor(subscription.monitor_ref, [:flush])
        
        new_subscriptions = Map.delete(state.subscriptions, name)
        new_restart_attempts = Map.delete(state.restart_attempts, name)
        new_state = %{state | 
          subscriptions: new_subscriptions,
          restart_attempts: new_restart_attempts
        }
        
        Logger.info("SubscriptionManager: Unregistered subscription #{name}")
        {:reply, :ok, new_state}
    end
  end
  
  def handle_call(:status, _from, state) do
    status = Enum.map(state.subscriptions, fn {name, sub} ->
      {name, %{
        status: sub.status,
        pid: sub.pid,
        last_check: sub.last_check,
        registered_at: sub.registered_at,
        restart_attempts: Map.get(state.restart_attempts, name, 0)
      }}
    end) |> Map.new()
    
    {:reply, status, state}
  end
  
  def handle_call({:restart, name}, _from, state) do
    case Map.get(state.subscriptions, name) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      subscription ->
        Logger.info("SubscriptionManager: Manually restarting subscription #{name}")
        new_state = restart_subscription_internal(name, subscription, state, :manual)
        {:reply, :ok, new_state}
    end
  end
  
  def handle_call({:health_check, name}, _from, state) do
    case Map.get(state.subscriptions, name) do
      nil ->
        {:reply, false, state}
      
      subscription ->
        is_healthy = Process.alive?(subscription.pid)
        {:reply, is_healthy, state}
    end
  end
  
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find the subscription that went down
    case Enum.find(state.subscriptions, fn {_name, sub} -> sub.monitor_ref == ref end) do
      {name, subscription} ->
        Logger.warning("SubscriptionManager: Subscription #{name} went down: #{inspect(reason)}")
        
        new_state = restart_subscription_internal(name, subscription, state, reason)
        {:noreply, new_state}
      
      nil ->
        Logger.warning("SubscriptionManager: Received DOWN message for unknown process")
        {:noreply, state}
    end
  end
  
  def handle_info(:health_check, state) do
    # Check health of all subscriptions
    new_state = perform_health_checks(state)
    
    # Schedule next health check
    Process.send_after(self(), :health_check, state.monitor_interval)
    
    {:noreply, new_state}
  end
  
  def handle_info({:restart_subscription, name}, state) do
    case Map.get(state.subscriptions, name) do
      nil ->
        Logger.warning("SubscriptionManager: Cannot restart unknown subscription #{name}")
        {:noreply, state}
      
      subscription ->
        new_state = restart_subscription_internal(name, subscription, state, :delayed_restart)
        {:noreply, new_state}
    end
  end
  
  # Private Functions
  
  defp perform_health_checks(state) do
    now = System.monotonic_time(:millisecond)
    
    updated_subscriptions = Enum.map(state.subscriptions, fn {name, subscription} ->
      is_alive = Process.alive?(subscription.pid)
      status = if is_alive, do: :healthy, else: :failed
      
      updated_subscription = %{subscription | 
        status: status,
        last_check: now
      }
      
      if not is_alive and subscription.status == :healthy do
        Logger.warning("SubscriptionManager: Subscription #{name} health check failed")
        # Schedule restart with backoff
        schedule_restart(name, Map.get(state.restart_attempts, name, 0))
      end
      
      {name, updated_subscription}
    end) |> Map.new()
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  defp restart_subscription_internal(name, subscription, state, reason) do
    attempts = Map.get(state.restart_attempts, name, 0)
    
    if attempts >= state.max_restart_attempts do
      Logger.error("SubscriptionManager: Subscription #{name} exceeded max restart attempts (#{attempts})")
      
      # Mark as failed and stop trying
      updated_subscription = %{subscription | status: :failed_permanently}
      new_subscriptions = Map.put(state.subscriptions, name, updated_subscription)
      
      %{state | subscriptions: new_subscriptions}
    else
      Logger.info("SubscriptionManager: Attempting to restart subscription #{name} (attempt #{attempts + 1}/#{state.max_restart_attempts})")
      
      try do
        # Call the restart function
        case subscription.restart_fun.() do
          {:ok, new_pid} ->
            Logger.info("SubscriptionManager: Successfully restarted subscription #{name} with new PID #{inspect(new_pid)}")
            
            # Stop monitoring old process and start monitoring new one
            Process.demonitor(subscription.monitor_ref, [:flush])
            new_ref = Process.monitor(new_pid)
            
            updated_subscription = %{subscription | 
              pid: new_pid,
              monitor_ref: new_ref,
              status: :healthy,
              last_check: System.monotonic_time(:millisecond)
            }
            
            new_subscriptions = Map.put(state.subscriptions, name, updated_subscription)
            new_restart_attempts = Map.delete(state.restart_attempts, name)  # Reset on success
            
            %{state | 
              subscriptions: new_subscriptions,
              restart_attempts: new_restart_attempts
            }
          
          {:error, restart_reason} ->
            Logger.error("SubscriptionManager: Failed to restart subscription #{name}: #{inspect(restart_reason)}")
            
            new_restart_attempts = Map.put(state.restart_attempts, name, attempts + 1)
            schedule_restart(name, attempts + 1)
            
            %{state | restart_attempts: new_restart_attempts}
        end
      rescue
        error ->
          Logger.error("SubscriptionManager: Exception during restart of #{name}: #{inspect(error)}")
          
          new_restart_attempts = Map.put(state.restart_attempts, name, attempts + 1)
          schedule_restart(name, attempts + 1)
          
          %{state | restart_attempts: new_restart_attempts}
      end
    end
  end
  
  defp schedule_restart(subscription_name, attempt) do
    # Exponential backoff: base * 2^attempt, with some jitter
    backoff_ms = @restart_backoff_base * :math.pow(2, attempt) |> round()
    jitter = :rand.uniform(1000)  # Add up to 1 second of jitter
    delay = backoff_ms + jitter
    
    Logger.info("SubscriptionManager: Scheduling restart of #{subscription_name} in #{delay}ms")
    Process.send_after(self(), {:restart_subscription, subscription_name}, delay)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
