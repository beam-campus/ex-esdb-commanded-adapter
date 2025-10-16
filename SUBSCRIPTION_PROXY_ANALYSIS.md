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

## ✅ IMPLEMENTED: PubSub-Based Health & Metrics Monitoring

### Implementation Status

As of 2025-01-27, we have successfully implemented a comprehensive PubSub-based health and metrics monitoring system for the ExESDB Commanded Adapter. This implementation maintains **100% backward compatibility** with existing Commanded applications while adding rich monitoring capabilities.

### 🎯 Core Implementation

#### **1. SubscriptionProxy Enhancements**

The `SubscriptionProxy` now publishes detailed health events throughout its lifecycle:

```elixir
# Health events published to :ex_esdb_system PubSub
# Topic: "subscription_health:#{store_id}:#{subscription_name}"

# Proxy lifecycle events
:proxy_started           # Published on GenServer init
:proxy_stopped          # Published on normal termination  
:proxy_crashed          # Published by SubscriptionGuard on unexpected death

# Registration lifecycle events
:registration_started   # Published when registration attempt begins
:registration_success   # Published on successful ExESDB registration
:registration_failed    # Published when registration fails (with error details)

# Circuit breaker events (from SubscriptionGuard)
:circuit_breaker_opened # Published when failure threshold reached
:circuit_breaker_closed # Published when circuit breaker resets
```

**Key Features:**
- **Non-blocking**: Health event publishing wrapped in `try/rescue` - never affects core functionality
- **Rich metadata**: Includes proxy PID, subscriber PID, subscription details, error information, timestamps
- **Error resilient**: Failed PubSub publishing logged but doesn't impact event processing

#### **2. SubscriptionGuard Enhancements**

The `SubscriptionGuard` now provides comprehensive circuit breaker monitoring:

```elixir
# Circuit breaker thresholds
@max_failures 5
@backoff_period 60  # seconds

# Published events
defp record_registration_failure(store_id, subscription_name, reason) do
  # ... increment failure count ...
  
  if count + 1 >= @max_failures do
    publish_health_event(store_id, subscription_name, :circuit_breaker_opened, %{
      failure_count: count + 1, 
      reason: reason
    })
  end
end
```

#### **3. SubscriptionMetrics Integration**

The `SubscriptionMetrics` module now publishes performance metrics:

```elixir
# Metrics events published to :ex_esdb_system PubSub
# Topic: "subscription_metrics:#{store_id}:#{subscription_name}"

publish_metrics_event(store_id, subscription_name, :registration_attempt, %{
  result: :ok | {:error, reason},
  timestamp: timestamp
})
```

### 🔍 **Backward Compatibility Analysis**

#### **✅ Core Commanded Interface UNCHANGED**

All essential Commanded EventStore.Adapter functions work exactly as before:

```elixir
# 1. Persistent subscriptions - WORKS IDENTICALLY
{:ok, proxy_pid} = ExESDB.Commanded.Adapter.subscribe_to(
  adapter_meta, "$all", "my_subscription", self(), :origin, []
)

# 2. Transient subscriptions - WORKS IDENTICALLY  
:ok = ExESDB.Commanded.Adapter.subscribe(adapter_meta, "$all")

# 3. Unsubscribe - WORKS IDENTICALLY
:ok = ExESDB.Commanded.Adapter.unsubscribe(adapter_meta, proxy_pid)

# 4. Event processing - IDENTICAL FLOW
receive do
  {:events, [%Commanded.EventStore.RecordedEvent{} = event]} ->
    # Process event - same as before
end
```

#### **✅ Event Processing Flow PRESERVED**

```elixir
# Lines 144-157: Core event handling UNCHANGED
def handle_info({:events, [%ExESDB.Schema.EventRecord{} = event_record]}, state) do
  handle_single_event(event_record, state)  # ← SAME AS BEFORE
  {:noreply, state}
end

# Lines 374-385: Event conversion & forwarding UNCHANGED
recorded_event = EventConverter.convert_event_record(event_record)  # ← SAME AS BEFORE
send(state.subscriber, {:events, [recorded_event]})                # ← SAME AS BEFORE
```

#### **✅ Subscription Management PRESERVED**

```elixir
# Unsubscribe handling - core logic identical
def handle_info(:unsubscribe, state) do
  {:stop, :normal, state}  # ← SAME AS BEFORE - triggers terminate/2
end

# Cleanup function - ExESDB interaction unchanged
defp handle_unsubscribe(state) do
  API.remove_subscription(state.store, state.type, state.selector, state.name)  # ← SAME AS BEFORE
  notify_health_monitor(:subscription_unregistered, state)                      # ← NEW (non-blocking)
end
```

### 🏗️ **Event Schema & Topics**

#### **Health Events Schema**
```elixir
%{
  store_id: atom(),
  subscription_name: String.t(),
  event_type: :registration_started | :registration_success | :registration_failed | 
              :proxy_started | :proxy_stopped | :proxy_crashed |
              :circuit_breaker_opened | :circuit_breaker_closed,
  timestamp: integer(),
  metadata: %{
    source: :subscription_proxy | :subscription_guard,
    proxy_pid: pid(),
    subscriber_pid: pid(),
    subscription_type: atom(),
    selector: String.t(),
    # ... additional event-specific metadata
  }
}
```

#### **Topic Patterns**
1. **Subscription Health:** `"subscription_health:#{store_id}:#{subscription_name}"`
2. **Subscription Metrics:** `"subscription_metrics:#{store_id}:#{subscription_name}"`
3. **Store Health Summary:** `"health_summary:#{store_id}"` (for future implementation)

### 🎁 **Benefits Delivered**

#### **1. Complete Observability**
- Real-time visibility into subscription lifecycle events
- Detailed error tracking with context
- Circuit breaker state monitoring
- Performance metrics collection

#### **2. Decoupled Architecture**  
- Health monitors can subscribe independently
- Multiple consumers can process the same events
- Easy to add new monitoring capabilities
- No tight coupling between producers and consumers

#### **3. Production Ready**
- Non-blocking health event publishing
- Comprehensive error handling
- Backward compatible with existing applications
- Rich metadata for debugging and alerting

### 🚀 **Usage Examples**

#### **Health Event Consumer**
```elixir
defmodule MyApp.SubscriptionHealthMonitor do
  use GenServer
  
  def init(store_id) do
    # Subscribe to all health events for a store
    topic_pattern = "subscription_health:#{store_id}:*"
    # Note: PubSub doesn't support wildcards, so subscribe to specific subscriptions
    
    {:ok, %{store_id: store_id}}
  end
  
  def handle_info({:subscription_health, event}, state) do
    case event.event_type do
      :circuit_breaker_opened ->
        send_alert("Circuit breaker opened for #{event.subscription_name}")
      :proxy_crashed ->
        send_alert("Subscription proxy crashed: #{event.subscription_name}")
      _ ->
        :ok
    end
    
    {:noreply, state}
  end
end
```

#### **Metrics Dashboard**
```elixir
defmodule MyApp.SubscriptionDashboard do
  def get_subscription_health(store_id) do
    # Subscribe to health events and build real-time dashboard
    Phoenix.PubSub.subscribe(:ex_esdb_system, "health_summary:#{store_id}")
    
    # Process health events to show:
    # - Active subscriptions
    # - Failed registrations  
    # - Circuit breaker status
    # - Recent crashes
  end
end
```

### 📊 **Verification Results**

| Component | Status | Verification |
|-----------|--------|-------------|
| **Commanded Interface** | ✅ **IDENTICAL** | All `subscribe_to/6`, `subscribe/2`, `unsubscribe/2` work unchanged |
| **Event Processing** | ✅ **IDENTICAL** | Event flow `ExESDB → Proxy → EventConverter → Subscriber` unchanged |
| **Error Handling** | ✅ **ENHANCED** | Health events wrapped in `try/rescue`, never fail main flow |
| **Performance** | ✅ **MAINTAINED** | Health publishing is async, no blocking operations added |
| **Memory Usage** | ✅ **MINIMAL IMPACT** | Only additional metadata storage for health events |

### 🔮 **Next Steps for Monitoring**

With the PubSub foundation in place, the ExESDB server can now implement:

1. **SubscriptionHealthTracker** - Aggregate health data and detect patterns
2. **SubscriptionAlerting** - Generate alerts based on health events  
3. **SubscriptionDashboard** - Real-time monitoring interface
4. **SubscriptionMetricsCollector** - Performance analysis and reporting
5. **Event Persistence** - Store health events for historical analysis

### 📝 **Summary**

The PubSub-based health and metrics implementation successfully:
- ✅ **Maintains 100% backward compatibility** with existing Commanded applications
- ✅ **Adds comprehensive monitoring** without affecting core functionality  
- ✅ **Provides rich observability** into subscription health and performance
- ✅ **Enables decoupled monitoring architecture** for scalable operational visibility
- ✅ **Uses robust error handling** to ensure monitoring never impacts business logic

Existing Commanded applications will continue to work exactly as before, while gaining access to powerful monitoring capabilities through the `:ex_esdb_system` PubSub interface.
