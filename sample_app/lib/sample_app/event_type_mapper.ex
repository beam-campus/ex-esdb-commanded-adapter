defmodule SampleApp.EventTypeMapper do
  @moduledoc """
  Event type mapper for converting Elixir module names to clean event type strings.
  
  This is required by the ExESDB.Commanded.Adapter to properly serialize
  and deserialize event types when storing and retrieving events.
  
  The mapper tries to call the `event_type/0` function on event modules to get
  clean semantic event types. If that fails, it falls back to using the module name.
  """

  @doc """
  Converts an Elixir module name (atom) or string to an event type string.
  
  First tries to call the `event_type/0` function on the module to get a clean
  semantic event type. If that fails, falls back to removing the "Elixir." prefix.
  
  ## Examples
  
      iex> SampleApp.EventTypeMapper.to_event_type(SampleApp.Domain.InitializePoll.EventV1)
      "poll_initialized:v1"
      
      iex> SampleApp.EventTypeMapper.to_event_type(SampleApp.Domain.CastVote.EventV1)
      "vote_casted:v1"
      
      iex> SampleApp.EventTypeMapper.to_event_type("Elixir.MyApp.SomeEvent")
      "MyApp.SomeEvent"
  """
  def to_event_type(module_name) when is_atom(module_name) do
    try do
      # Try to call event_type/0 on the module to get clean event type
      module_name.event_type()
    rescue
      # If module doesn't have event_type/0 function, fall back to module name
      _ ->
        module_name
        |> to_string()
        |> String.replace("Elixir.", "")
    end
  end

  def to_event_type(event_type_string) when is_binary(event_type_string) do
    # If it's already a string, check if it looks like a module name
    if String.starts_with?(event_type_string, "Elixir.") do
      # Try to convert to module and get clean event type
      try do
        module = String.to_existing_atom(event_type_string)
        module.event_type()
      rescue
        _ ->
          # Fall back to removing Elixir prefix
          String.replace(event_type_string, "Elixir.", "")
      end
    else
      # Already a clean string, return as-is
      event_type_string
    end
  end
end
