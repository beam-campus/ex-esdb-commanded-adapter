defmodule RegulateGreenhouse.Infrastructure.Supervisor do
  @moduledoc """
  Supervisor for all infrastructure components that provide reliability and resilience.
  
  This supervisor manages:
  - Circuit breakers
  - Event deduplicator
  - Subscription manager
  - Health checker
  """
  
  use Supervisor
  require Logger
  
  alias RegulateGreenhouse.Infrastructure.{
    CircuitBreaker,
    EventDeduplicator,
    SubscriptionManager,
    HealthChecker
  }
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    Logger.info("Infrastructure.Supervisor: Starting reliability infrastructure")
    
    children = [
      # Start event deduplicator first
      {EventDeduplicator, []},
      
      # Start circuit breakers
      {CircuitBreaker, [
        name: :greenhouse_projection_circuit_breaker,
        config: %{
          failure_threshold: 5,
          recovery_timeout: 60_000,  # 1 minute
          reset_timeout: 30_000      # 30 seconds
        }
      ]},
      
      # Start subscription manager
      {SubscriptionManager, [
        monitor_interval: :timer.seconds(30),
        max_restart_attempts: 5
      ]},
      
      # Start health checker last
      {HealthChecker, [
        check_interval: :timer.minutes(1)
      ]}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Register all event-type projections for monitoring.
  """
  def register_event_type_projections do
    # Get status of all event type projections
    case RegulateGreenhouse.Projections.EventTypeProjectionManager.status() do
      projections when is_list(projections) ->
        Enum.each(projections, fn {event_type, status} ->
          case status do
            {:running, pid: pid} ->
              restart_fun = fn ->
                RegulateGreenhouse.Projections.EventTypeProjectionManager.restart_projection(event_type)
              end
              
              SubscriptionManager.register_subscription(
                "#{event_type}_projection",
                pid,
                restart_fun
              )
              Logger.info("Infrastructure.Supervisor: Registered #{event_type} projection for monitoring")
            
            :not_running ->
              Logger.warning("Infrastructure.Supervisor: #{event_type} projection not running")
          end
        end)
        :ok
      
      error ->
        Logger.error("Infrastructure.Supervisor: Failed to get projection status: #{inspect(error)}")
        error
    end
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end
end
