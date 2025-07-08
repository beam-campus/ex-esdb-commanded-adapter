defmodule RegulateGreenhouse.CommandedPatch do
  @moduledoc """
  Patches Commanded to handle ExESDB.Schema.EventRecord messages.
  
  This module provides utility functions to convert ExESDB events
  to Commanded format when they bypass the adapter proxy.
  """

  alias Commanded.EventStore.RecordedEvent

  @doc """
  Converts an ExESDB.Schema.EventRecord to Commanded.EventStore.RecordedEvent.
  """
  def convert_event(%ExESDB.Schema.EventRecord{} = event_record) do
    %RecordedEvent{
      event_id: event_record.event_id,
      event_number: event_record.event_number,
      stream_id: event_record.event_stream_id,
      stream_version: event_record.event_number,
      causation_id: Map.get(event_record.metadata, :causation_id),
      correlation_id: Map.get(event_record.metadata, :correlation_id),
      event_type: event_record.event_type,
      data: event_record.data,
      metadata: event_record.metadata || %{},
      created_at: event_record.created
    }
  end

  def convert_event(%RecordedEvent{} = event), do: event

  @doc """
  Converts a list of events, handling both ExESDB and Commanded formats.
  """
  def convert_events(events) when is_list(events) do
    Enum.map(events, &convert_event/1)
  end
end
