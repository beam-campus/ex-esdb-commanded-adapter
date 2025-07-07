defmodule RegulateGreenhouse.Infrastructure.HealthChecker do
  @moduledoc """
    Health checker service that monitors the overall health of the greenhouse system.

  This module provides health checks for critical components including:
  - Event store connectivity
  - Subscription status
  - Cache availability
  - Circuit breaker states
  """

  use GenServer
  require Logger

  alias RegulateGreenhouse.Infrastructure.CircuitBreaker
  alias RegulateGreenhouse.Infrastructure.EventDeduplicator
  alias RegulateGreenhouse.Infrastructure.SubscriptionManager

  defstruct [
    :check_interval,
    :last_check,
    :health_status,
    :alerts
  ]

  @default_check_interval :timer.minutes(1)
  @alert_retention_time :timer.hours(24)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current system health status.
  """
  def health_status do
    GenServer.call(__MODULE__, :health_status)
  end

  @doc """
  Get recent health alerts.
  """
  def get_alerts do
    GenServer.call(__MODULE__, :get_alerts)
  end

  @doc """
  Force a health check.
  """
  def force_check do
    GenServer.call(__MODULE__, :force_check)
  end

  @doc """
  Clear all alerts.
  """
  def clear_alerts do
    GenServer.call(__MODULE__, :clear_alerts)
  end

  # Server Implementation

  @impl GenServer
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)

    state = %__MODULE__{
      check_interval: check_interval,
      last_check: nil,
      health_status: %{},
      alerts: []
    }

    # Schedule the first health check
    # Start after 1 second
    Process.send_after(self(), :health_check, 1000)

    Logger.info("HealthChecker started with check interval #{check_interval}ms")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:health_status, _from, state) do
    {:reply, state.health_status, state}
  end

  def handle_call(:get_alerts, _from, state) do
    # Filter out old alerts
    now = DateTime.utc_now()

    recent_alerts =
      Enum.filter(state.alerts, fn alert ->
        DateTime.diff(now, alert.timestamp, :millisecond) < @alert_retention_time
      end)

    {:reply, recent_alerts, %{state | alerts: recent_alerts}}
  end

  def handle_call(:force_check, _from, state) do
    new_state = perform_health_check(state)
    {:reply, new_state.health_status, new_state}
  end

  def handle_call(:clear_alerts, _from, state) do
    Logger.info("HealthChecker: Clearing all alerts")
    {:reply, :ok, %{state | alerts: []}}
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)

    # Schedule next health check
    Process.send_after(self(), :health_check, state.check_interval)

    {:noreply, new_state}
  end

  # Private Functions

  defp perform_health_check(state) do
    Logger.debug("HealthChecker: Starting health check")
    now = DateTime.utc_now()

    health_checks = %{
      event_store: check_event_store(),
      subscriptions: check_subscriptions(),
      cache_service: check_cache_service(),
      event_deduplicator: check_event_deduplicator(),
      circuit_breakers: check_circuit_breakers(),
      memory_usage: check_memory_usage(),
      process_count: check_process_count()
    }

    # Determine overall health
    overall_health = determine_overall_health(health_checks)

    # Generate alerts for failed checks
    new_alerts = generate_alerts(health_checks, state.alerts, now)

    # Log health status
    if overall_health.status != :healthy do
      Logger.warning(
        "HealthChecker: System health is #{overall_health.status}: #{overall_health.message}"
      )
    else
      Logger.debug("HealthChecker: System health is healthy")
    end

    %{
      state
      | last_check: now,
        health_status: Map.put(health_checks, :overall, overall_health),
        alerts: new_alerts
    }
  end

  defp check_event_store do
    try do
      # Try to get greenhouse list to test connectivity
      case RegulateGreenhouse.CacheService.list_greenhouses() do
        greenhouses when is_list(greenhouses) ->
          %{
            status: :healthy,
            message: "Event store accessible",
            details: %{greenhouse_count: length(greenhouses)}
          }

        error ->
          %{status: :unhealthy, message: "Event store query failed", details: %{error: error}}
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Event store connection failed",
          details: %{error: inspect(error)}
        }
    end
  end

  defp check_subscriptions do
    try do
      status = SubscriptionManager.status()

      failed_count =
        Enum.count(status, fn {_name, sub_status} ->
          sub_status.status in [:failed, :failed_permanently]
        end)

      total_count = map_size(status)

      cond do
        total_count == 0 ->
          %{status: :warning, message: "No subscriptions registered", details: status}

        failed_count == 0 ->
          %{
            status: :healthy,
            message: "All subscriptions healthy",
            details: %{total: total_count, failed: 0}
          }

        failed_count < total_count ->
          %{
            status: :warning,
            message: "Some subscriptions failed",
            details: %{total: total_count, failed: failed_count}
          }

        true ->
          %{
            status: :unhealthy,
            message: "All subscriptions failed",
            details: %{total: total_count, failed: failed_count}
          }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Subscription manager unavailable",
          details: %{error: inspect(error)}
        }
    end
  end

  defp check_cache_service do
    try do
      # Test cache connectivity
      test_key = "health_check_#{System.unique_integer()}"

      case Cachex.put(:greenhouse_read_models, test_key, :test_value, ttl: 1000) do
        {:ok, true} ->
          # Clean up test key
          Cachex.del(:greenhouse_read_models, test_key)
          %{status: :healthy, message: "Cache service operational"}

        error ->
          %{status: :unhealthy, message: "Cache service failed", details: %{error: error}}
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Cache service unavailable",
          details: %{error: inspect(error)}
        }
    end
  end

  defp check_event_deduplicator do
    try do
      stats = EventDeduplicator.stats()
      %{status: :healthy, message: "Event deduplicator operational", details: stats}
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Event deduplicator unavailable",
          details: %{error: inspect(error)}
        }
    end
  end

  defp check_circuit_breakers do
    # Check if circuit breakers are registered and get their states
    circuit_breakers = [:greenhouse_projection_circuit_breaker]

    cb_status =
      Enum.map(circuit_breakers, fn cb_name ->
        try do
          case Process.whereis(cb_name) do
            nil ->
              {cb_name, %{status: :not_found, message: "Circuit breaker not registered"}}

            _pid ->
              state = CircuitBreaker.state(cb_name)
              status = if state.state == :open, do: :warning, else: :healthy
              {cb_name, %{status: status, details: state}}
          end
        rescue
          error ->
            {cb_name,
             %{
               status: :unhealthy,
               message: "Circuit breaker check failed",
               details: %{error: inspect(error)}
             }}
        end
      end)
      |> Map.new()

    overall_cb_status =
      if Enum.any?(cb_status, fn {_name, status} -> status.status == :unhealthy end) do
        :unhealthy
      else
        :healthy
      end

    %{status: overall_cb_status, message: "Circuit breakers checked", details: cb_status}
  end

  defp check_memory_usage do
    try do
      memory_info = :erlang.memory()
      total_mb = div(memory_info[:total], 1024 * 1024)
      processes_mb = div(memory_info[:processes], 1024 * 1024)

      # Alert if memory usage is over 1GB
      status = if total_mb > 1024, do: :warning, else: :healthy

      %{
        status: status,
        message: "Memory usage: #{total_mb}MB total, #{processes_mb}MB processes",
        details: %{
          total_mb: total_mb,
          processes_mb: processes_mb,
          system_mb: div(memory_info[:system], 1024 * 1024)
        }
      }
    rescue
      error ->
        %{status: :unhealthy, message: "Memory check failed", details: %{error: inspect(error)}}
    end
  end

  defp check_process_count do
    try do
      process_count = length(Process.list())

      # Alert if process count is over 10,000
      status = if process_count > 10_000, do: :warning, else: :healthy

      %{
        status: status,
        message: "Process count: #{process_count}",
        details: %{count: process_count}
      }
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Process count check failed",
          details: %{error: inspect(error)}
        }
    end
  end

  defp determine_overall_health(health_checks) do
    critical_components = [:event_store, :subscriptions, :cache_service]

    # Check critical components first
    critical_issues =
      Enum.filter(critical_components, fn component ->
        Map.get(health_checks, component, %{}).status == :unhealthy
      end)

    warning_issues =
      Enum.filter(health_checks, fn {_component, status} ->
        status.status == :warning
      end)

    cond do
      length(critical_issues) > 0 ->
        %{
          status: :unhealthy,
          message: "Critical components failed: #{Enum.join(critical_issues, ", ")}",
          critical_issues: critical_issues,
          warning_count: length(warning_issues)
        }

      length(warning_issues) > 0 ->
        %{
          status: :warning,
          message: "#{length(warning_issues)} components have warnings",
          warning_count: length(warning_issues)
        }

      true ->
        %{
          status: :healthy,
          message: "All systems operational"
        }
    end
  end

  defp generate_alerts(health_checks, existing_alerts, timestamp) do
    # Generate alerts for failed health checks
    new_alerts =
      Enum.flat_map(health_checks, fn {component, status} ->
        case status.status do
          :unhealthy ->
            [
              %{
                id: "#{component}_unhealthy_#{System.unique_integer()}",
                component: component,
                severity: :error,
                message: status.message,
                details: Map.get(status, :details, %{}),
                timestamp: timestamp
              }
            ]

          :warning ->
            [
              %{
                id: "#{component}_warning_#{System.unique_integer()}",
                component: component,
                severity: :warning,
                message: status.message,
                details: Map.get(status, :details, %{}),
                timestamp: timestamp
              }
            ]

          _ ->
            []
        end
      end)

    # Combine with existing alerts, removing duplicates by component
    all_alerts = new_alerts ++ existing_alerts

    # Keep only the most recent alert per component
    latest_alerts =
      all_alerts
      |> Enum.group_by(& &1.component)
      |> Enum.map(fn {_component, alerts} ->
        Enum.max_by(alerts, &DateTime.to_unix(&1.timestamp))
      end)

    # Filter out old alerts
    now = DateTime.utc_now()

    Enum.filter(latest_alerts, fn alert ->
      DateTime.diff(now, alert.timestamp, :millisecond) < @alert_retention_time
    end)
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
