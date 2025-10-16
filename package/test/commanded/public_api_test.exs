defmodule ExESDB.Commanded.PublicAPITest do
  use ExUnit.Case
  alias ExESDB.Commanded.Adapter
  alias ExESDB.Schema.EventRecord
  alias Commanded.EventStore.RecordedEvent

  describe "public conversion API" do
    test "convert_event_record/1 converts ExESDB EventRecord to Commanded RecordedEvent" do
      # Create a sample ExESDB EventRecord
      event_record = %EventRecord{
        event_id: "test-event-id",
        event_number: 5,
        event_stream_id: "test-stream",
        event_type: "TestEvent",
        data: %{"test" => "data"},
        metadata: %{
          correlation_id: "corr-123",
          causation_id: "cause-456",
          stream_version: 4  # 0-based in ExESDB
        },
        created: ~U[2023-01-01 12:00:00Z]
      }

      # Call the public API function
      result = Adapter.convert_event_record(event_record)

      # Verify the result
      assert %RecordedEvent{} = result
      assert result.event_id == "test-event-id"
      assert result.event_number == 5
      assert result.stream_id == "test-stream"
      assert result.event_type == "TestEvent"
      assert result.data == %{"test" => "data"}
      assert result.correlation_id == "corr-123"
      assert result.causation_id == "cause-456"
      # EventConverter removes stream_version from metadata, so fallback uses event_number + 1
      assert result.stream_version == 6  # event_number 5 + 1
      assert result.created_at == ~U[2023-01-01 12:00:00Z]
    end

    test "convert_events/1 converts a list of events" do
      event_record1 = %EventRecord{
        event_id: "event-1",
        event_number: 1,
        event_stream_id: "test-stream",
        event_type: "Event1",
        data: %{"event" => 1},
        metadata: %{stream_version: 0},  # 0-based
        created: ~U[2023-01-01 12:00:00Z]
      }

      event_record2 = %EventRecord{
        event_id: "event-2", 
        event_number: 2,
        event_stream_id: "test-stream",
        event_type: "Event2",
        data: %{"event" => 2},
        metadata: %{stream_version: 1},  # 0-based
        created: ~U[2023-01-01 12:00:01Z]
      }

      events = [event_record1, event_record2]
      
      # Call the public API function
      results = Adapter.convert_events(events)

      # Verify the results
      assert length(results) == 2
      assert [%RecordedEvent{}, %RecordedEvent{}] = results
      
      [result1, result2] = results
      assert result1.event_id == "event-1"
      assert result1.stream_version == 2  # event_number 1 + 1
      assert result2.event_id == "event-2"
      assert result2.stream_version == 3  # event_number 2 + 1
    end

    test "convert_events/1 handles mixed event types" do
      event_record = %EventRecord{
        event_id: "event-1",
        event_number: 1,
        event_stream_id: "test-stream",
        event_type: "ExESDBEvent",
        data: %{"type" => "esdb"},
        metadata: %{},
        created: ~U[2023-01-01 12:00:00Z]
      }

      recorded_event = %RecordedEvent{
        event_id: "event-2",
        event_number: 2,
        stream_id: "test-stream",
        stream_version: 2,
        event_type: "CommandedEvent",
        data: %{"type" => "commanded"},
        metadata: %{},
        created_at: ~U[2023-01-01 12:00:01Z]
      }

      events = [event_record, recorded_event]
      
      # Call the public API function
      results = Adapter.convert_events(events)

      # Verify the results
      assert length(results) == 2
      assert [%RecordedEvent{}, %RecordedEvent{}] = results
      
      [result1, result2] = results
      assert result1.event_id == "event-1"
      assert result1.event_type == "ExESDBEvent"
      assert result2.event_id == "event-2"
      assert result2.event_type == "CommandedEvent"
      # Second event should be unchanged since it was already a RecordedEvent
      assert result2 == recorded_event
    end
  end
end