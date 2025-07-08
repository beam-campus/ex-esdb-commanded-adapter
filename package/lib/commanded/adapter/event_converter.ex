defmodule ExESDB.Commanded.Adapter.EventConverter do
  @moduledoc """
  Handles conversion between ExESDB events and Commanded events.
  """

  alias ExESDB.Commanded.Mapper

  @doc """
  Parses metadata from various formats (binary, map, or nil).
  """
  def parse_metadata(nil), do: %{}
  def parse_metadata(metadata) when is_map(metadata), do: metadata

  def parse_metadata(metadata) when is_binary(metadata) do
    try do
      case Jason.decode(metadata) do
        {:ok, parsed} when is_map(parsed) ->
          # Convert string keys to atoms if they match expected metadata keys
          parsed
          |> Enum.reduce(%{}, fn {k, v}, acc ->
            case k do
              "causation_id" -> Map.put(acc, :causation_id, v)
              "correlation_id" -> Map.put(acc, :correlation_id, v)
              "stream_version" -> Map.put(acc, :stream_version, v)
              _ -> Map.put(acc, k, v)
            end
          end)

        {:ok, _} ->
          %{}

        {:error, _} ->
          %{}
      end
    rescue
      _ -> %{}
    end
  end

  def parse_metadata(_), do: %{}

  @doc """
  Converts a single ExESDB EventRecord to Commanded RecordedEvent.
  """
  def convert_event_record(%ExESDB.Schema.EventRecord{} = event_record) do
    parsed_metadata = parse_metadata(event_record.metadata)

    # Don't put stream_version in metadata - let the fallback clause handle it
    # The stream_version should be in the RecordedEvent struct itself, not metadata
    clean_metadata = %{
      correlation_id: Map.get(parsed_metadata, :correlation_id),
      causation_id: Map.get(parsed_metadata, :causation_id)
    }

    # Create event record with clean metadata (no stream_version in metadata)
    normalized_event_record = %{event_record | metadata: clean_metadata}

    # Use the fallback clause of Mapper which will set stream_version correctly
    Mapper.to_recorded_event(normalized_event_record)
  end

  @doc """
  Converts a list of events to Commanded format.
  """
  def convert_events(events) when is_list(events) do
    Enum.map(events, fn
      %ExESDB.Schema.EventRecord{} = event_record ->
        convert_event_record(event_record)

      %Commanded.EventStore.RecordedEvent{} = recorded_event ->
        # Already in correct format
        recorded_event
    end)
  end

end
