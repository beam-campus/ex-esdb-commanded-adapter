defmodule RegulateGreenhouse.Projections.Handlers.TemperatureEventHandler do
  @moduledoc """
  Handler for temperature-related events (set and measured).
  
  This handler updates greenhouse read models with temperature information.
  """
  
  require Logger
  
  alias RegulateGreenhouse.Events.{TemperatureSet, TemperatureMeasured}
  alias RegulateGreenhouse.ReadModels.GreenhouseReadModel
  
  @cache_name :greenhouse_read_models
  
  @doc """
  Handle a temperature-related event for a specific greenhouse.
  """
  def handle_event(%{data: data, event_type: "desired_temperature_set:v1"}, greenhouse_id) do
    
    event = struct(TemperatureSet, atomize_keys(data))
    
    update_greenhouse_read_model(greenhouse_id, fn read_model ->
      %{read_model | 
        target_temperature: event.target_temperature,
        updated_at: event.set_at,
        event_count: (read_model.event_count || 0) + 1
      }
    end, :temperature_set)
  end
  
  def handle_event(%{data: data, event_type: "temperature_measured:v1"}, greenhouse_id) do
    # Handle both struct and map data formats
    temperature_value = case data do
      %{temperature: temp} -> temp
      %{"temperature" => temp} -> temp
      %RegulateGreenhouse.Events.TemperatureMeasured{temperature: temp} -> temp
      _ -> "unknown"
    end
    
    
    event = struct(TemperatureMeasured, atomize_keys(data))
    
    update_greenhouse_read_model(greenhouse_id, fn read_model ->
      %{read_model | 
        current_temperature: event.temperature,
        updated_at: event.measured_at,
        event_count: (read_model.event_count || 0) + 1
      }
    end, :temperature_measured)
  end
  
  def handle_event(event, greenhouse_id) do
    Logger.warning("TemperatureEventHandler: Unhandled event type #{event.event_type} for greenhouse #{greenhouse_id}")
    :ok
  end
  
  # Private helper functions
  
  defp update_greenhouse_read_model(greenhouse_id, update_fn, event_type) do
    
    case Cachex.get(@cache_name, greenhouse_id) do
      {:ok, nil} ->
        Logger.warning("TemperatureEventHandler: Greenhouse #{greenhouse_id} not found in cache for #{event_type}, will retry...")
        # Retry after a short delay to handle race condition where measurement events
        # arrive before GreenhouseCreated event is processed
        :timer.sleep(100)
        case Cachex.get(@cache_name, greenhouse_id) do
          {:ok, nil} ->
            Logger.error("TemperatureEventHandler: Greenhouse #{greenhouse_id} still not found in cache for #{event_type} after retry")
            {:error, :not_found}
          {:ok, read_model} ->
            do_update_read_model(greenhouse_id, read_model, update_fn, event_type)
          {:error, reason} = error ->
            Logger.error("TemperatureEventHandler: Cache error for #{greenhouse_id} on retry: #{inspect(reason)}")
            error
        end

      {:ok, read_model} ->
        do_update_read_model(greenhouse_id, read_model, update_fn, event_type)

      {:error, reason} = error ->
        Logger.error("TemperatureEventHandler: Cache error for #{greenhouse_id}: #{inspect(reason)}")
        error
    end
  end

  defp do_update_read_model(greenhouse_id, read_model, update_fn, event_type) do
    updated_model = update_fn.(read_model)
    updated_model = %{updated_model | status: GreenhouseReadModel.calculate_status(updated_model)}
    
    case Cachex.put(@cache_name, greenhouse_id, updated_model) do
      {:ok, true} -> :ok
      error ->
        Logger.error("TemperatureEventHandler: Failed to cache updated greenhouse #{greenhouse_id}: #{inspect(error)}")
        raise "Cache operation failed: #{inspect(error)}"
    end
    
    # Publish update for real-time UI updates
    case Phoenix.PubSub.broadcast(
      RegulateGreenhouse.PubSub, 
      "greenhouse_updates", 
      {:greenhouse_updated, updated_model, event_type}
    ) do
      :ok -> :ok
      error ->
        Logger.warning("TemperatureEventHandler: Failed to publish #{event_type}: #{inspect(error)}")
        # Don't fail the event processing for PubSub failures
    end

    {:ok, updated_model}
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
