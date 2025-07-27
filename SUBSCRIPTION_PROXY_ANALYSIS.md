# Subscription Proxy Re-Registration Mechanism Analysis

## Current Re-Registration System

### How It Works

1. **Initial Registration** (on `init/1`):
   ```elixir
   case register_with_store(state) do
     :ok -> 
       schedule_reregistration(:initial)  # 5 seconds
       {:ok, %{state | subscription_registered: true}}
   end
   ```

2. **Periodic Re-Registration** (via `:reregister_pid` message):
   ```elixir
   def handle_info(:reregister_pid, state) do
     case register_with_store(state) do
       :ok -> schedule_reregistration(:normal)      # 30 seconds
       {:error, _} -> schedule_reregistration(:retry) # 10 seconds
     end
   end
   ```

3. **Registration Intervals**:
   - **Initial**: 5 seconds (fast startup)
   - **Normal**: 30 seconds (steady state)
   - **Retry**: 10 seconds (on failure)

### Core Registration Function
```elixir
defp register_with_store(state) do
  API.save_subscription(
    state.store,          # :greenhouse_tycoon
    state.type,          # :by_event_type or :by_stream
    state.selector,      # "greenhouse_initialized:v1" or "$all"
    state.name,          # "greenhouse_initialized_to_pubsub_v1"
    state.start_version, # 0
    self()               # Current PID - THIS IS THE KEY!
  )
end
```

## Problems with Current Approach

### 1. **Race Conditions During Leader Election**
```
Leader Election Scenario:
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Old Leader    │    │   New Leader    │    │ Subscription    │
│                 │    │                 │    │     Proxy       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │ Events routed here    │                       │
         │ ◄──────────────────── │                       │
         │                       │                       │
         ▼ (Leader dies)         │                       │
         X                       │                       │
                                 │                       │
                                 │ ◄─ re-register (up to 30s delay)
                                 │                       │
```

**Issue**: Events can be lost for up to 30 seconds during leader transitions.

### 2. **No Event-Driven Re-Registration**
- Re-registration is purely **time-based** (polling)
- No notification when ExESDB leadership changes
- No detection of emitter process restarts

### 3. **Silent Failures**
```elixir
{:error, reason} -> 
  Logger.warning("Failed to re-register PID: #{inspect(reason)}")
  schedule_reregistration(:retry)  # Just retry later
```
- Warnings get lost in logs
- No alerting for prolonged failures
- No circuit breaker pattern

### 4. **Process Restart Re-Registration Gap**
```
Process Restart Scenario:
┌─────────────────┐    ┌─────────────────┐
│  Old Proxy PID  │    │  New Proxy PID  │
│   (PID: 1234)   │    │   (PID: 5678)   │
└─────────────────┘    └─────────────────┘
         │                       │
         ▼ (Crash)               │
         X                       │ init() -> register_with_store()
                                 │ ◄─ Events still routed to 1234!
                                 │
                                 │ (Wait 5 seconds for :initial)
                                 │ ◄─ Finally re-registers with 5678
```

## Proposed Improvements

### 1. **Event-Driven Re-Registration**

Add Phoenix PubSub subscription for ExESDB cluster events:

```elixir
defmodule ExESDB.Commanded.Adapter.SubscriptionProxy do
  @cluster_events_topic "exesdb:cluster_events"
  
  def init(metadata) do
    # ... existing init code ...
    
    # Subscribe to cluster events for immediate re-registration
    Phoenix.PubSub.subscribe(:ex_esdb_events, @cluster_events_topic)
    
    # Reduced polling frequency since we have event-driven updates
    schedule_reregistration(:initial)
    
    {:ok, %{state | subscription_registered: true}}
  end
  
  def handle_info({:cluster_leader_changed, new_leader}, state) do
    Logger.info("SubscriptionProxy[#{state.name}]: Leader changed to #{new_leader}, re-registering")
    
    case register_with_store(state) do
      :ok -> 
        Logger.info("SubscriptionProxy[#{state.name}]: Successfully re-registered with new leader")
        {:noreply, state}
      {:error, reason} ->
        Logger.error("SubscriptionProxy[#{state.name}]: Failed to re-register with new leader: #{inspect(reason)}")
        schedule_reregistration(:retry)
        {:noreply, state}
    end
  end
  
  def handle_info({:emitter_restarted, emitter_topic}, state) do
    # Re-register if this affects our subscription
    if emitter_affects_subscription?(emitter_topic, state) do
      Logger.info("SubscriptionProxy[#{state.name}]: Emitter restarted for #{emitter_topic}, re-registering")
      register_with_store(state)
    end
    {:noreply, state}
  end
end
```

### 2. **Health Monitoring with Circuit Breaker**

```elixir
defmodule ExESDB.Commanded.Adapter.SubscriptionProxy do
  defstruct [
    # ... existing fields ...
    :consecutive_failures,
    :last_successful_registration,
    :health_status  # :healthy, :degraded, :failed
  ]
  
  def handle_info(:reregister_pid, state) do
    case register_with_store(state) do
      :ok ->
        new_state = %{state | 
          consecutive_failures: 0,
          last_successful_registration: DateTime.utc_now(),
          health_status: :healthy
        }
        
        schedule_reregistration(:normal)
        {:noreply, new_state}
        
      {:error, reason} ->
        failures = state.consecutive_failures + 1
        
        new_state = %{state | 
          consecutive_failures: failures,
          health_status: health_status_for_failures(failures)
        }
        
        case new_state.health_status do
          :degraded when failures == 3 ->
            Logger.warning("SubscriptionProxy[#{state.name}]: Entering degraded state (#{failures} failures)")
            
          :failed when failures >= 5 ->
            Logger.error("SubscriptionProxy[#{state.name}]: CRITICAL - Entering failed state (#{failures} failures)")
            # Notify monitoring systems
            notify_monitoring_failure(state)
            
          _ -> :ok
        end
        
        interval = exponential_backoff_interval(failures)
        schedule_reregistration_with_interval(interval)
        {:noreply, new_state}
    end
  end
  
  defp health_status_for_failures(failures) when failures < 3, do: :healthy
  defp health_status_for_failures(failures) when failures < 5, do: :degraded
  defp health_status_for_failures(_), do: :failed
  
  defp exponential_backoff_interval(failures) do
    # Start at 1 second, max out at 60 seconds
    min(60_000, 1000 * :math.pow(2, failures))
  end
end
```

### 3. **Immediate Registration on Restart**

Update the supervisor to trigger immediate re-registration:

```elixir
defmodule ExESDB.Commanded.Adapter.SubscriptionProxySupervisor do
  def restart_proxy(store_id, subscription_name) do
    supervisor_name = supervisor_name(store_id)
    
    # Find the proxy by subscription name
    case find_proxy_by_name(supervisor_name, subscription_name) do
      {:ok, pid} ->
        # Terminate the old proxy
        DynamicSupervisor.terminate_child(supervisor_name, pid)
        
        # The supervisor will automatically restart it
        # The new process will immediately register in init()
        {:ok, :restarted}
        
      {:error, :not_found} ->
        {:error, :proxy_not_found}
    end
  end
  
  defp find_proxy_by_name(supervisor_name, subscription_name) do
    supervisor_name
    |> DynamicSupervisor.which_children()
    |> Enum.find_value(fn {_, pid, _, _} ->
      case GenServer.call(pid, :get_subscription_name, 1000) do
        ^subscription_name -> {:ok, pid}
        _ -> nil
      end
    rescue
      _ -> nil
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end
end
```

### 4. **Registration Verification**

Add verification that registration actually worked:

```elixir
defp register_with_store(state) do
  # Step 1: Register the subscription
  case API.save_subscription(state.store, state.type, state.selector, state.name, state.start_version, self()) do
    :ok ->
      # Step 2: Verify the registration took effect
      case verify_registration(state) do
        :ok -> 
          Logger.debug("SubscriptionProxy[#{state.name}]: Registration verified")
          :ok
        {:error, reason} ->
          Logger.warning("SubscriptionProxy[#{state.name}]: Registration verification failed: #{inspect(reason)}")
          {:error, {:verification_failed, reason}}
      end
      
    {:error, reason} ->
      {:error, reason}
  end
end

defp verify_registration(state) do
  case API.get_subscription(state.store, state.type, state.selector, state.name) do
    {:ok, %{pid: pid}} when pid == self() ->
      :ok
    {:ok, %{pid: other_pid}} ->
      {:error, {:wrong_pid, other_pid, self()}}
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 5. **Monitoring and Alerting Dashboard**

```elixir
defmodule ExESDB.Commanded.Adapter.SubscriptionProxyMonitor do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end
  
  def handle_call(:get_health_status, _from, state) do
    # Collect health data from all subscription proxies
    status = collect_proxy_health_status()
    {:reply, status, state}
  end
  
  defp collect_proxy_health_status do
    # Get all stores
    stores = Application.get_env(:ex_esdb_commanded, :stores, [])
    
    Enum.map(stores, fn store_id ->
      proxies = ExESDB.Commanded.Adapter.SubscriptionProxySupervisor.list_proxies(store_id)
      
      proxy_statuses = Enum.map(proxies, fn {_, pid, _, _} ->
        case GenServer.call(pid, :get_health_status, 1000) do
          {:ok, status} -> status
          _ -> %{pid: pid, status: :unreachable}
        end
      rescue
        _ -> %{pid: pid, status: :error}
      end)
      
      %{
        store_id: store_id,
        proxy_count: length(proxies),
        healthy_count: count_by_status(proxy_statuses, :healthy),
        degraded_count: count_by_status(proxy_statuses, :degraded),
        failed_count: count_by_status(proxy_statuses, :failed),
        proxies: proxy_statuses
      }
    end)
  end
end
```

### 6. **Configuration for Tuning**

```elixir
# config/config.exs
config :ex_esdb_commanded, :subscription_proxy,
  # Re-registration intervals
  initial_reregister_interval: :timer.seconds(1),     # Faster startup
  normal_reregister_interval: :timer.seconds(15),    # More frequent polling
  retry_reregister_interval: :timer.seconds(3),      # Faster retry
  
  # Health monitoring
  max_consecutive_failures: 5,
  failure_notification_threshold: 3,
  enable_exponential_backoff: true,
  max_backoff_interval: :timer.seconds(60),
  
  # Event-driven re-registration
  enable_cluster_event_subscriptions: true,
  cluster_events_topic: "exesdb:cluster_events",
  
  # Verification
  enable_registration_verification: true,
  verification_timeout: :timer.seconds(2)
```

## Summary of Improvements

1. **Event-Driven Re-Registration**: Immediate response to cluster changes
2. **Health Monitoring**: Track failures and system health
3. **Exponential Backoff**: Reduce load during outages
4. **Registration Verification**: Ensure registration actually worked
5. **Monitoring Dashboard**: Visibility into proxy health
6. **Configurable Intervals**: Tune for your specific needs

These improvements would eliminate the 30-second window where events can be lost and provide much better observability into the subscription system's health.
