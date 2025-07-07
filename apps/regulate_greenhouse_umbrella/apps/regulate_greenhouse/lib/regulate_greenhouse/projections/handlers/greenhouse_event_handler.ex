defmodule RegulateGreenhouse.Projections.Handlers.GreenhouseEventHandler do
  @moduledoc """
  Handler for greenhouse lifecycle events (creation, deletion, etc.).
  
  This handler manages the core greenhouse read model lifecycle.
  """
  
  require Logger
  
  alias RegulateGreenhouse.Events.GreenhouseCreated
  alias RegulateGreenhouse.ReadModels.GreenhouseReadModel
  
  @cache_name :greenhouse_read_models
  
  @doc """
  Handle a greenhouse-related event for a specific greenhouse.
  """
  def handle_event(%{data: data, event_type: "initialized:v1"}, greenhouse_id) do
    Logger.info("GreenhouseEventHandler: Processing initialized:v1 event for greenhouse #{greenhouse_id}")
    Logger.debug("GreenhouseEventHandler: Event data: #{inspect(data)}")
    
    # Deserialize the event data
    event = struct(GreenhouseCreated, atomize_keys(data))
    Logger.debug("GreenhouseEventHandler: Deserialized event: #{inspect(event)}")
    
    read_model = %GreenhouseReadModel{
      greenhouse_id: event.greenhouse_id,
      name: event.name,
      location: event.location,
      target_temperature: event.target_temperature,
      target_humidity: event.target_humidity,
      target_light: nil,
      current_temperature: nil,
      current_humidity: nil,
      current_light: nil,
      event_count: 1,
      created_at: event.created_at,
      updated_at: event.created_at
    }
    
    # Calculate status and store in cache
    read_model = %{read_model | status: GreenhouseReadModel.calculate_status(read_model)}
    Logger.info("GreenhouseEventHandler: Created read model for #{greenhouse_id}: #{inspect(read_model)}")
    
    case Cachex.put(@cache_name, greenhouse_id, read_model) do
      {:ok, true} -> 
        Logger.info("GreenhouseEventHandler: Successfully cached greenhouse #{greenhouse_id}")
        :ok
      error ->
        Logger.error("GreenhouseEventHandler: Failed to cache greenhouse #{greenhouse_id}: #{inspect(error)}")
        raise "Cache operation failed: #{inspect(error)}"
    end
    
    # Publish update for real-time UI updates
    case Phoenix.PubSub.broadcast(
      RegulateGreenhouse.PubSub, 
      "greenhouse_updates", 
      {:greenhouse_created, read_model}
    ) do
      :ok -> :ok
      error ->
        Logger.warning("GreenhouseEventHandler: Failed to publish greenhouse_created: #{inspect(error)}")
        # Don't fail the event processing for PubSub failures
    end
    
    :ok
  end
  
  def handle_event(event, greenhouse_id) do
    Logger.warning("GreenhouseEventHandler: Unhandled event type #{event.event_type} for greenhouse #{greenhouse_id}")
    :ok
  end
  
  # Helper function to convert string keys to atoms
  defp atomize_keys(%{__struct__: _} = struct_data) do
    # If it's already a struct, convert to map first
    struct_data
    |> Map.from_struct()
    |> atomize_keys()
  end
  
  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> 
      case k do
        k when is_binary(k) -> {String.to_atom(k), v}
        k -> {k, v}
      end
    end)
    |> Enum.into(%{})
  end
  
  defp atomize_keys(data), do: data
end
