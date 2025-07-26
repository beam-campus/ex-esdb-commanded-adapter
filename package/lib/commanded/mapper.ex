defmodule ExESDB.Commanded.Mapper do
  @moduledoc """
    A mapper for Commanded to use ExESDB as the event store.
  """
  alias Commanded.EventStore.EventData, as: EventData
  alias Commanded.EventStore.RecordedEvent, as: RecordedEvent
  alias Commanded.EventStore.SnapshotData, as: SnapshotData

  alias ExESDB.Schema.EventRecord, as: EventRecord
  alias ExESDB.Schema.NewEvent, as: NewEvent
  alias ExESDB.Schema.SnapshotRecord, as: SnapshotRecord

  alias ExESDB.Commanded.EventTypeMapper, as: EventTypeMapper

  require Logger

  alias UUIDv7

  @doc """
    Converts a Commanded EventData struct to an ExESDB.Schema.NewEvent struct.
  """
  @spec to_new_event(EventData.t(), EventTypeMapper.t()) :: NewEvent.t()
  def to_new_event(event_data, event_type_mapper)
      when is_struct(event_data, EventData) and is_atom(event_type_mapper) do
    %NewEvent{
      event_id: UUIDv7.generate(),
      event_type: map_event_type_to_readable(event_data.event_type, event_type_mapper),
      data_content_type: 1,
      metadata_content_type: 1,
      data: event_data.data,
      metadata: %{
        correlation_id: event_data.correlation_id,
        causation_id: event_data.causation_id
      }
    }
  end

  @doc """
  Converts an ExESDB.Schema.EventRecord struct to a Commanded RecordedEvent struct.
  """
  @spec to_recorded_event(EventRecord.t()) :: RecordedEvent.t()
  def to_recorded_event(
        %{
          metadata: %{
            stream_version: stream_version,
            correlation_id: correlation_id,
            causation_id: causation_id
          }
        } = event_record
      )
      when is_struct(event_record, EventRecord) do
    # Convert ExESDB 0-based stream_version to Commanded 1-based
    commanded_stream_version =
      case stream_version do
        version when is_integer(version) and version >= 0 -> version + 1
        version -> version
      end

    %RecordedEvent{
      event_id: event_record.event_id,
      event_number: event_record.event_number,
      event_type: event_record.event_type,
      data: event_record.data,
      metadata: event_record.metadata,
      created_at: event_record.created,
      stream_id: event_record.event_stream_id,
      stream_version: commanded_stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id
    }
  end

  # Fallback clause for events without properly structured metadata
  def to_recorded_event(%EventRecord{} = event_record) do
    # Extract metadata safely
    metadata = event_record.metadata || %{}

    # Use event_number as stream_version if not properly set, then convert to Commanded 1-based
    stream_version =
      case Map.get(metadata, :stream_version) do
        # Convert 0-based to 1-based
        version when is_integer(version) and version >= 0 ->
          version + 1

        _ ->
          # Use event_number as fallback and convert to 1-based
          case event_record.event_number do
            num when is_integer(num) and num >= 0 -> num + 1
            num -> num
          end
      end

    %RecordedEvent{
      event_id: event_record.event_id,
      event_number: event_record.event_number,
      event_type: event_record.event_type,
      data: event_record.data,
      metadata: metadata,
      created_at: event_record.created,
      stream_id: event_record.event_stream_id,
      stream_version: stream_version,
      correlation_id: Map.get(metadata, :correlation_id),
      causation_id: Map.get(metadata, :causation_id)
    }
  end

  @doc """
    Converts a Commanded SnapshotData struct to an ExESDB.Schema.SnapshotRecord struct.
  """
  @spec to_snapshot_record(SnapshotData.t()) :: SnapshotRecord.t()
  def to_snapshot_record(snapshot_data)
      when is_struct(snapshot_data, SnapshotData) do
    # Handle case where created_at is nil by using current time
    created_at = snapshot_data.created_at || DateTime.utc_now()

    %SnapshotRecord{
      source_uuid: snapshot_data.source_uuid,
      source_version: snapshot_data.source_version,
      source_type: snapshot_data.source_type,
      data: snapshot_data.data,
      metadata: snapshot_data.metadata,
      created_at: created_at,
      created_epoch: DateTime.to_unix(created_at, :millisecond)
    }
  end

  @doc """
    Converts an ExESDB.Schema.SnapshotRecord struct to a Commanded SnapshotData struct.
  """
  def to_snapshot_data(snapshot_record)
      when is_struct(snapshot_record, SnapshotRecord),
      do: %SnapshotData{
        source_uuid: snapshot_record.source_uuid,
        source_version: snapshot_record.source_version,
        source_type: snapshot_record.source_type,
        data: snapshot_record.data,
        metadata: snapshot_record.metadata,
        created_at: snapshot_record.created_at
      }

  # Event type mapping functions

  defp map_event_type_to_readable(event_type, event_type_mapper)
       when is_atom(event_type) and is_atom(event_type_mapper) do
    try do
      event_type_mapper.to_event_type(event_type)
    rescue
      error ->
        Logger.error("Failed to map event type #{inspect(event_type)}: #{inspect(error)}")
        to_string(event_type)
    end
  end

  defp map_event_type_to_readable(event_type, event_type_mapper)
       when is_binary(event_type) and is_atom(event_type_mapper) do
    try do
      event_type
      |> String.to_atom()
      |> map_event_type_to_readable(event_type_mapper)
    rescue
      error ->
        Logger.error("Failed to convert string event type #{inspect(event_type)} to atom: #{inspect(error)}")
        event_type
    end
  end
end
