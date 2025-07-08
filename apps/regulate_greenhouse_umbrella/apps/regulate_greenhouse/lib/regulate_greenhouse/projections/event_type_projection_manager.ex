defmodule RegulateGreenhouse.Projections.EventTypeProjectionManager do
  @moduledoc """
  Manages event-type-based projections for better scalability and performance.
  
  Instead of subscribing to $all and filtering, this creates specific subscriptions
  for each event type and routes events directly to the appropriate handlers.
  
  This approach:
  - Creates finite subscriptions (one per event type)
  - Enables natural parallelization
  - Reduces unnecessary event processing
  - Provides better resource utilization
  """
  
  use Supervisor
  require Logger
  
  alias RegulateGreenhouse.Projections.Handlers.{
    GreenhouseEventHandler,
    TemperatureEventHandler,
    HumidityEventHandler,
    LightEventHandler
  }
  
  # Define event type to handler mappings
  # Using readable, versioned event type names
  @event_handlers %{
    "initialized:v1" => GreenhouseEventHandler,
    "desired_temperature_set:v1" => TemperatureEventHandler,
    "temperature_measured:v1" => TemperatureEventHandler,
    "desired_humidity_set:v1" => HumidityEventHandler,
    "humidity_measured:v1" => HumidityEventHandler,
    "desired_light_set:v1" => LightEventHandler,
    "light_measured:v1" => LightEventHandler
  }
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    Logger.info("EventTypeProjectionManager: Starting event-type-based projections")
    
    # Create one projection supervisor per event type
    children = Enum.map(@event_handlers, fn {event_type, handler_module} ->
      %{
        id: :"#{event_type}_projection",
        start: {
          RegulateGreenhouse.Projections.EventTypeProjection,
          :start_link,
          [[
            event_type: event_type,
            handler_module: handler_module,
            name: :"#{event_type}_projection"
          ]]
        },
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      }
    end)
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Get status of all event type projections.
  """
  def status do
    Enum.map(@event_handlers, fn {event_type, _handler} ->
      projection_name = :"#{event_type}_projection"
      case Process.whereis(projection_name) do
        nil -> {event_type, :not_running}
        pid -> {event_type, :running, pid: pid}
      end
    end)
  end
  
  @doc """
  Restart a specific event type projection.
  """
  def restart_projection(event_type) when is_binary(event_type) do
    projection_id = :"#{event_type}_projection"
    
    case Supervisor.terminate_child(__MODULE__, projection_id) do
      :ok ->
        case Supervisor.restart_child(__MODULE__, projection_id) do
          {:ok, _pid} ->
            Logger.info("EventTypeProjectionManager: Restarted #{event_type} projection")
            :ok
          {:error, reason} ->
            Logger.error("EventTypeProjectionManager: Failed to restart #{event_type} projection: #{inspect(reason)}")
            {:error, reason}
        end
      {:error, reason} ->
        Logger.error("EventTypeProjectionManager: Failed to terminate #{event_type} projection: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Get the handler module for a specific event type.
  """
  def get_handler(event_type), do: Map.get(@event_handlers, event_type)
  
  @doc """
  Get all supported event types.
  """
  def supported_event_types, do: Map.keys(@event_handlers)
  
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
