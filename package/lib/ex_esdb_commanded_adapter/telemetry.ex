defmodule ExESDBCommandedAdapter.Telemetry do
  @moduledoc """
  Telemetry GenServer for the ExESDB Commanded Adapter package.
  
  This module is responsible only for monitoring and observability within
  the ex_esdb_commanded_adapter package. It follows proper separation of concerns by:
  
  1. Only handling telemetry events from this package
  2. Running as a supervised GenServer for reliability
  3. Broadcasting events through PubSub for external consumption
  4. Maintaining internal metrics and health state
  
  ## Responsibilities
  - Monitor command processing and event appending
  - Track aggregate lifecycle and state management
  - Monitor subscription proxy operations
  - Track event acknowledgment and delivery
  - Monitor adapter initialization and lifecycle
  - Collect command/event sourcing performance metrics
  
  ## Usage
  
  The telemetry server is automatically started by the adapter supervisor.
  To emit custom events from your code:
  
      ExESDBCommandedAdapter.Telemetry.emit(:command_handled, %{aggregate_id: "123", command: MyCommand, duration_us: 1500})
      ExESDBCommandedAdapter.Telemetry.emit(:event_appended, %{stream: "account-123", events: 2})
  
  To get current metrics:
  
      ExESDBCommandedAdapter.Telemetry.get_metrics()
      ExESDBCommandedAdapter.Telemetry.get_health()
  """
  
  use GenServer
  require Logger
  alias Phoenix.PubSub
  
  @pubsub_server :ex_esdb_commanded_metrics
  
  # Telemetry events this module handles
  @telemetry_events [
    [:ex_esdb_commanded_adapter, :command, :handled, :start],
    [:ex_esdb_commanded_adapter, :command, :handled, :stop],
    [:ex_esdb_commanded_adapter, :command, :handled, :error],
    [:ex_esdb_commanded_adapter, :event, :appended, :start],
    [:ex_esdb_commanded_adapter, :event, :appended, :stop],
    [:ex_esdb_commanded_adapter, :event, :appended, :error],
    [:ex_esdb_commanded_adapter, :aggregate, :loaded, :start],
    [:ex_esdb_commanded_adapter, :aggregate, :loaded, :stop],
    [:ex_esdb_commanded_adapter, :aggregate, :loaded, :error],
    [:ex_esdb_commanded_adapter, :subscription, :created],
    [:ex_esdb_commanded_adapter, :subscription, :started],
    [:ex_esdb_commanded_adapter, :subscription, :stopped],
    [:ex_esdb_commanded_adapter, :subscription, :event_received],
    [:ex_esdb_commanded_adapter, :subscription, :event_acked],
    [:ex_esdb_commanded_adapter, :subscription, :error],
    [:ex_esdb_commanded_adapter, :adapter, :initialized],
    [:ex_esdb_commanded_adapter, :adapter, :stopped],
    [:ex_esdb_commanded_adapter, :snapshot, :loaded],
    [:ex_esdb_commanded_adapter, :snapshot, :saved]
  ]
  
  # Metrics collection interval (30 seconds)
  @metrics_interval 30_000
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end
  
  @doc """
  Emit a telemetry event from application code.
  """
  def emit(event_name, metadata \\ %{}) when is_atom(event_name) do
    measurements = %{
      timestamp: System.monotonic_time(:microsecond),
      system_time: System.system_time(:microsecond)
    }
    :telemetry.execute([:ex_esdb_commanded_adapter, event_name], measurements, metadata)
  end
  
  @doc """
  Get current metrics summary.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Get current health status.
  """
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end
  
  @doc """
  Reset metrics counters.
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    # Attach telemetry handlers
    :telemetry.attach_many(
      "ex-esdb-commanded-adapter-telemetry",
      @telemetry_events,
      &handle_telemetry_event/4,
      %{}
    )
    
    # Schedule periodic metrics collection
    Process.send_after(self(), :collect_metrics, @metrics_interval)
    
    initial_state = %{
      # Command handling
      commands: %{
        handled: %{total: 0, errors: 0, avg_duration_us: 0},
        by_type: %{},
        by_aggregate: %{}
      },
      
      # Event appending
      events: %{
        appended: %{total: 0, errors: 0, avg_duration_us: 0, events_count: 0},
        by_stream: %{},
        by_aggregate_type: %{}
      },
      
      # Aggregate operations
      aggregates: %{
        loaded: %{total: 0, errors: 0, avg_duration_us: 0},
        by_type: %{},
        cache_hits: 0,
        cache_misses: 0
      },
      
      # Subscription management
      subscriptions: %{
        active: 0,
        created: 0,
        started: 0,
        stopped: 0,
        events_received: 0,
        events_acked: 0,
        errors: 0,
        by_name: %{}
      },
      
      # Snapshot operations
      snapshots: %{
        loaded: 0,
        saved: 0,
        by_aggregate_type: %{}
      },
      
      # Adapter lifecycle
      adapter: %{
        initialized_at: nil,
        restart_count: 0,
        last_error: nil
      },
      
      # System metrics
      system_metrics: %{},
      last_metrics_collection: DateTime.utc_now(),
      
      # Configuration
      config: Map.new(opts)
    }
    
    Logger.info("ExESDBCommandedAdapter.Telemetry started successfully")
    {:ok, initial_state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      commands: state.commands,
      events: state.events,
      aggregates: state.aggregates,
      subscriptions: state.subscriptions,
      snapshots: state.snapshots,
      adapter: state.adapter,
      system_metrics: state.system_metrics,
      last_updated: state.last_metrics_collection
    }
    
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:get_health, _from, state) do
    health = %{
      status: calculate_overall_health(state),
      command_health: calculate_command_health(state),
      event_health: calculate_event_health(state),
      aggregate_health: calculate_aggregate_health(state),
      subscription_health: calculate_subscription_health(state),
      adapter_health: calculate_adapter_health(state),
      node: Node.self(),
      timestamp: DateTime.utc_now()
    }
    
    {:reply, health, state}
  end
  
  @impl true
  def handle_call(:reset_metrics, _from, state) do
    reset_state = %{state |
      commands: %{handled: %{total: 0, errors: 0, avg_duration_us: 0}, by_type: %{}, by_aggregate: %{}},
      events: %{appended: %{total: 0, errors: 0, avg_duration_us: 0, events_count: 0}, by_stream: %{}, by_aggregate_type: %{}},
      aggregates: %{loaded: %{total: 0, errors: 0, avg_duration_us: 0}, by_type: %{}, cache_hits: 0, cache_misses: 0},
      subscriptions: %{active: 0, created: 0, started: 0, stopped: 0, events_received: 0, events_acked: 0, errors: 0, by_name: %{}},
      snapshots: %{loaded: 0, saved: 0, by_aggregate_type: %{}}
    }
    
    {:reply, :ok, reset_state}
  end
  
  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect system metrics
    system_metrics = collect_system_metrics()
    
    # Broadcast current state
    broadcast_metrics_update(state, system_metrics)
    
    # Schedule next collection
    Process.send_after(self(), :collect_metrics, @metrics_interval)
    
    updated_state = %{state |
      system_metrics: system_metrics,
      last_metrics_collection: DateTime.utc_now()
    }
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    updated_state = process_telemetry_event(event, measurements, metadata, state)
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(msg, state) do
    Logger.debug("ExESDBCommandedAdapter.Telemetry received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, _state) do
    # Detach telemetry handlers
    :telemetry.detach("ex-esdb-commanded-adapter-telemetry")
    Logger.info("ExESDBCommandedAdapter.Telemetry terminated: #{inspect(reason)}")
    :ok
  end
  
  ## Private Functions
  
  # Telemetry event handler (runs in caller's process)
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    # Send to GenServer for processing (non-blocking)
    send(__MODULE__, {:telemetry_event, event, measurements, metadata})
  end
  
  ## Pattern-matched telemetry event processors
  
  # Command handling events
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :command, :handled, :start], _measurements, _metadata, state) do
    state
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :command, :handled, :stop], measurements, metadata, state) do
    duration_us = Map.get(measurements, :duration, 0)
    command_type = Map.get(metadata, :command_type, :unknown)
    aggregate_type = Map.get(metadata, :aggregate_type, :unknown)
    
    current_handled = state.commands.handled
    new_total = current_handled.total + 1
    
    # Calculate new average duration
    current_avg = current_handled.avg_duration_us
    new_avg = if new_total > 1 do
      (current_avg * (new_total - 1) + duration_us) / new_total
    else
      duration_us
    end
    
    updated_handled = %{current_handled |
      total: new_total,
      avg_duration_us: new_avg
    }
    
    updated_commands = %{state.commands |
      handled: updated_handled,
      by_type: Map.update(state.commands.by_type, command_type, 1, &(&1 + 1)),
      by_aggregate: Map.update(state.commands.by_aggregate, aggregate_type, 1, &(&1 + 1))
    }
    
    # Check for performance issues
    if duration_us > 5_000_000 do  # > 5 seconds
      broadcast_performance_alert(:slow_command_handling, metadata, duration_us)
    end
    
    %{state | commands: updated_commands}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :command, :handled, :error], _measurements, metadata, state) do
    updated_handled = %{state.commands.handled |
      errors: state.commands.handled.errors + 1
    }
    
    updated_commands = %{state.commands | handled: updated_handled}
    
    broadcast_performance_alert(:command_handling_error, metadata, nil)
    
    %{state | commands: updated_commands}
  end
  
  # Event appending events
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :event, :appended, :start], _measurements, _metadata, state) do
    state
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :event, :appended, :stop], measurements, metadata, state) do
    duration_us = Map.get(measurements, :duration, 0)
    events_count = Map.get(metadata, :events_count, 1)
    stream_name = Map.get(metadata, :stream_name, :unknown)
    aggregate_type = Map.get(metadata, :aggregate_type, :unknown)
    
    current_appended = state.events.appended
    new_total = current_appended.total + 1
    new_events_count = current_appended.events_count + events_count
    
    # Calculate new average duration
    current_avg = current_appended.avg_duration_us
    new_avg = if new_total > 1 do
      (current_avg * (new_total - 1) + duration_us) / new_total
    else
      duration_us
    end
    
    updated_appended = %{current_appended |
      total: new_total,
      avg_duration_us: new_avg,
      events_count: new_events_count
    }
    
    updated_events = %{state.events |
      appended: updated_appended,
      by_stream: Map.update(state.events.by_stream, stream_name, events_count, &(&1 + events_count)),
      by_aggregate_type: Map.update(state.events.by_aggregate_type, aggregate_type, events_count, &(&1 + events_count))
    }
    
    %{state | events: updated_events}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :event, :appended, :error], _measurements, metadata, state) do
    updated_appended = %{state.events.appended |
      errors: state.events.appended.errors + 1
    }
    
    updated_events = %{state.events | appended: updated_appended}
    
    broadcast_performance_alert(:event_appending_error, metadata, nil)
    
    %{state | events: updated_events}
  end
  
  # Aggregate loading events
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :aggregate, :loaded, :start], _measurements, _metadata, state) do
    state
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :aggregate, :loaded, :stop], measurements, metadata, state) do
    duration_us = Map.get(measurements, :duration, 0)
    aggregate_type = Map.get(metadata, :aggregate_type, :unknown)
    from_cache = Map.get(metadata, :from_cache, false)
    
    current_loaded = state.aggregates.loaded
    new_total = current_loaded.total + 1
    
    # Calculate new average duration
    current_avg = current_loaded.avg_duration_us
    new_avg = if new_total > 1 do
      (current_avg * (new_total - 1) + duration_us) / new_total
    else
      duration_us
    end
    
    updated_loaded = %{current_loaded |
      total: new_total,
      avg_duration_us: new_avg
    }
    
    # Update cache metrics
    {cache_hits, cache_misses} = if from_cache do
      {state.aggregates.cache_hits + 1, state.aggregates.cache_misses}
    else
      {state.aggregates.cache_hits, state.aggregates.cache_misses + 1}
    end
    
    updated_aggregates = %{state.aggregates |
      loaded: updated_loaded,
      by_type: Map.update(state.aggregates.by_type, aggregate_type, 1, &(&1 + 1)),
      cache_hits: cache_hits,
      cache_misses: cache_misses
    }
    
    %{state | aggregates: updated_aggregates}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :aggregate, :loaded, :error], _measurements, metadata, state) do
    updated_loaded = %{state.aggregates.loaded |
      errors: state.aggregates.loaded.errors + 1
    }
    
    updated_aggregates = %{state.aggregates | loaded: updated_loaded}
    
    broadcast_performance_alert(:aggregate_loading_error, metadata, nil)
    
    %{state | aggregates: updated_aggregates}
  end
  
  # Subscription events
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :subscription, :created], _measurements, metadata, state) do
    subscription_name = Map.get(metadata, :subscription_name, :unknown)
    
    updated_subscriptions = %{state.subscriptions |
      created: state.subscriptions.created + 1,
      by_name: Map.update(state.subscriptions.by_name, subscription_name, %{created: 1, events_received: 0}, 
        fn stats -> %{stats | created: stats.created + 1} end)
    }
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :subscription, :started], _measurements, _metadata, state) do
    updated_subscriptions = %{state.subscriptions |
      active: state.subscriptions.active + 1,
      started: state.subscriptions.started + 1
    }
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :subscription, :stopped], _measurements, _metadata, state) do
    updated_subscriptions = %{state.subscriptions |
      active: max(0, state.subscriptions.active - 1),
      stopped: state.subscriptions.stopped + 1
    }
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :subscription, :event_received], _measurements, metadata, state) do
    subscription_name = Map.get(metadata, :subscription_name, :unknown)
    
    updated_subscriptions = %{state.subscriptions |
      events_received: state.subscriptions.events_received + 1,
      by_name: Map.update(state.subscriptions.by_name, subscription_name, %{created: 0, events_received: 1}, 
        fn stats -> %{stats | events_received: stats.events_received + 1} end)
    }
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :subscription, :event_acked], _measurements, _metadata, state) do
    updated_subscriptions = %{state.subscriptions |
      events_acked: state.subscriptions.events_acked + 1
    }
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :subscription, :error], _measurements, metadata, state) do
    updated_subscriptions = %{state.subscriptions |
      errors: state.subscriptions.errors + 1
    }
    
    broadcast_performance_alert(:subscription_error, metadata, nil)
    
    %{state | subscriptions: updated_subscriptions}
  end
  
  # Snapshot events
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :snapshot, :loaded], _measurements, metadata, state) do
    aggregate_type = Map.get(metadata, :aggregate_type, :unknown)
    
    updated_snapshots = %{state.snapshots |
      loaded: state.snapshots.loaded + 1,
      by_aggregate_type: Map.update(state.snapshots.by_aggregate_type, aggregate_type, %{loaded: 1, saved: 0}, 
        fn stats -> %{stats | loaded: stats.loaded + 1} end)
    }
    
    %{state | snapshots: updated_snapshots}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :snapshot, :saved], _measurements, metadata, state) do
    aggregate_type = Map.get(metadata, :aggregate_type, :unknown)
    
    updated_snapshots = %{state.snapshots |
      saved: state.snapshots.saved + 1,
      by_aggregate_type: Map.update(state.snapshots.by_aggregate_type, aggregate_type, %{loaded: 0, saved: 1}, 
        fn stats -> %{stats | saved: stats.saved + 1} end)
    }
    
    %{state | snapshots: updated_snapshots}
  end
  
  # Adapter lifecycle events
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :adapter, :initialized], _measurements, _metadata, state) do
    updated_adapter = %{state.adapter |
      initialized_at: DateTime.utc_now(),
      restart_count: state.adapter.restart_count + 1
    }
    
    %{state | adapter: updated_adapter}
  end
  
  defp process_telemetry_event([:ex_esdb_commanded_adapter, :adapter, :stopped], _measurements, metadata, state) do
    error = Map.get(metadata, :error)
    
    updated_adapter = %{state.adapter |
      last_error: error
    }
    
    if error do
      broadcast_performance_alert(:adapter_stopped_with_error, metadata, nil)
    end
    
    %{state | adapter: updated_adapter}
  end
  
  # Catch-all for unknown events
  defp process_telemetry_event(event, _measurements, _metadata, state) do
    Logger.debug("Unknown telemetry event: #{inspect(event)}")
    state
  end
  
  ## Helper Functions
  
  # System metrics collection
  defp collect_system_metrics do
    %{
      memory: :erlang.memory(),
      process_count: length(Process.list()),
      commanded_app_processes: count_commanded_processes(),
      timestamp: DateTime.utc_now()
    }
  rescue
    _ -> %{error: "Failed to collect system metrics", timestamp: DateTime.utc_now()}
  end
  
  defp count_commanded_processes do
    Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} -> 
          Enum.any?(dict, fn {key, _value} -> 
            to_string(key) =~ "commanded" or to_string(key) =~ "aggregate"
          end)
        _ -> false
      end
    end)
    |> length()
  rescue
    _ -> 0
  end
  
  ## Health Calculations
  
  defp calculate_overall_health(state) do
    command_healthy = calculate_command_health(state) in [:healthy, :degraded]
    event_healthy = calculate_event_health(state) in [:healthy, :degraded]
    aggregate_healthy = calculate_aggregate_health(state) in [:healthy, :degraded]
    subscription_healthy = calculate_subscription_health(state) in [:healthy, :degraded]
    
    cond do
      command_healthy and event_healthy and aggregate_healthy and subscription_healthy -> :healthy
      command_healthy and event_healthy and aggregate_healthy -> :degraded
      true -> :unhealthy
    end
  end
  
  defp calculate_command_health(state) do
    if state.commands.handled.total > 0 do
      error_rate = state.commands.handled.errors / state.commands.handled.total
      avg_duration_ms = state.commands.handled.avg_duration_us / 1000
      
      cond do
        error_rate < 0.01 and avg_duration_ms < 3000 -> :healthy
        error_rate < 0.05 and avg_duration_ms < 10000 -> :degraded
        true -> :unhealthy
      end
    else
      :unknown
    end
  end
  
  defp calculate_event_health(state) do
    if state.events.appended.total > 0 do
      error_rate = state.events.appended.errors / state.events.appended.total
      avg_duration_ms = state.events.appended.avg_duration_us / 1000
      
      cond do
        error_rate < 0.01 and avg_duration_ms < 2000 -> :healthy
        error_rate < 0.05 and avg_duration_ms < 8000 -> :degraded
        true -> :unhealthy
      end
    else
      :unknown
    end
  end
  
  defp calculate_aggregate_health(state) do
    if state.aggregates.loaded.total > 0 do
      error_rate = state.aggregates.loaded.errors / state.aggregates.loaded.total
      avg_duration_ms = state.aggregates.loaded.avg_duration_us / 1000
      cache_hit_rate = if (state.aggregates.cache_hits + state.aggregates.cache_misses) > 0 do
        state.aggregates.cache_hits / (state.aggregates.cache_hits + state.aggregates.cache_misses)
      else
        0.0
      end
      
      cond do
        error_rate < 0.01 and avg_duration_ms < 1000 and cache_hit_rate > 0.7 -> :healthy
        error_rate < 0.05 and avg_duration_ms < 5000 and cache_hit_rate > 0.4 -> :degraded
        true -> :unhealthy
      end
    else
      :unknown
    end
  end
  
  defp calculate_subscription_health(state) do
    if state.subscriptions.events_received > 0 do
      error_rate = state.subscriptions.errors / state.subscriptions.events_received
      ack_rate = if state.subscriptions.events_received > 0 do
        state.subscriptions.events_acked / state.subscriptions.events_received
      else
        0.0
      end
      
      cond do
        error_rate < 0.01 and ack_rate > 0.95 -> :healthy
        error_rate < 0.05 and ack_rate > 0.80 -> :degraded
        true -> :unhealthy
      end
    else
      :unknown
    end
  end
  
  defp calculate_adapter_health(state) do
    if state.adapter.initialized_at do
      time_since_init = DateTime.diff(DateTime.utc_now(), state.adapter.initialized_at, :second)
      
      cond do
        state.adapter.last_error == nil and time_since_init > 300 -> :healthy  # 5 minutes stable
        state.adapter.last_error == nil and time_since_init > 60 -> :degraded   # 1 minute stable
        true -> :unhealthy
      end
    else
      :unhealthy
    end
  end
  
  ## Broadcasting Functions
  
  defp broadcast_metrics_update(state, system_metrics) do
    message = %{
      type: :metrics_update,
      package: :ex_esdb_commanded_adapter,
      node: Node.self(),
      metrics: %{
        commands: state.commands,
        events: state.events,
        aggregates: state.aggregates,
        subscriptions: state.subscriptions,
        snapshots: state.snapshots,
        adapter: state.adapter,
        system: system_metrics
      },
      timestamp: DateTime.utc_now()
    }
    
    PubSub.broadcast(@pubsub_server, "esdb:commanded:metrics", {:metrics_update, message})
  end
  
  defp broadcast_performance_alert(alert_type, metadata, duration) do
    alert = %{
      type: :performance_alert,
      alert: alert_type,
      package: :ex_esdb_commanded_adapter,
      node: Node.self(),
      duration_us: duration,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
    
    PubSub.broadcast(@pubsub_server, "esdb:commanded:alerts", {:performance_alert, alert})
  end
end
