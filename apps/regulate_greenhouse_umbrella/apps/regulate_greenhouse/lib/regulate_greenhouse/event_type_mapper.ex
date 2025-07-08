defmodule RegulateGreenhouse.EventTypeMapper do
  @moduledoc """
  Maps between Commanded event module names and readable, versioned event types.
  
  This ensures that events are stored with implementation-agnostic, 
  readable names rather than module names.
  """

  @event_type_mappings %{
    "Elixir.RegulateGreenhouse.Events.GreenhouseInitialized" => "initialized:v1",
    "Elixir.RegulateGreenhouse.Events.TemperatureSet" => "desired_temperature_set:v1",
    "Elixir.RegulateGreenhouse.Events.TemperatureMeasured" => "temperature_measured:v1",
    "Elixir.RegulateGreenhouse.Events.HumiditySet" => "desired_humidity_set:v1",
    "Elixir.RegulateGreenhouse.Events.HumidityMeasured" => "humidity_measured:v1",
    "Elixir.RegulateGreenhouse.Events.LightSet" => "desired_light_set:v1",
    "Elixir.RegulateGreenhouse.Events.LightMeasured" => "light_measured:v1"
  }

  @doc """
  Maps a Commanded event module name to a readable, versioned event type.
  Used when writing events to the event store.
  """
  def to_event_type(event_module) when is_atom(event_module) do
    event_module
    |> Atom.to_string()
    |> to_event_type()
  end

  def to_event_type(event_module_string) when is_binary(event_module_string) do
    Map.get(@event_type_mappings, event_module_string, event_module_string)
  end

  @doc """
  Maps a readable event type back to the corresponding module name.
  Used when reading events from the event store.
  """
  def from_event_type(readable_type) when is_binary(readable_type) do
    # Create reverse mapping
    reverse_mappings = @event_type_mappings
    |> Enum.map(fn {k, v} -> {v, k} end)
    |> Map.new()
    
    Map.get(reverse_mappings, readable_type, readable_type)
  end

  @doc """
  Returns all supported event type mappings.
  """
  def mappings, do: @event_type_mappings
end
