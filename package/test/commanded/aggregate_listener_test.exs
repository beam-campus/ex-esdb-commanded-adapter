defmodule ExESDB.Commanded.AggregateListenerTest do
  use ExUnit.Case, async: true
  require Logger

  alias ExESDB.Commanded.AggregateListener

  def unique_store_id, do: :"test_store_#{System.unique_integer([:positive])}"
  def unique_stream_id, do: "test-stream-#{System.unique_integer([:positive])}"

  setup do
    store_id = unique_store_id()
    stream_id = unique_stream_id()
    
    %{store_id: store_id, stream_id: stream_id}
  end

  describe "start_link/1" do
    test "starts a new listener with valid config", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      assert {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      # Clean up
      AggregateListener.stop(pid)
    end

    test "starts listeners with different stream_ids", %{store_id: store_id} do
      config1 = %{
        store_id: store_id,
        stream_id: unique_stream_id(),
        subscriber: self(),
        replay_historical_events?: false
      }
      
      config2 = %{
        store_id: store_id,
        stream_id: unique_stream_id(),
        subscriber: self(),
        replay_historical_events?: false
      }

      assert {:ok, pid1} = AggregateListener.start_link(config1)
      Process.sleep(50) # Allow registration to complete
      assert {:ok, pid2} = AggregateListener.start_link(config2)
      Process.sleep(50) # Allow registration to complete
      
      # Different streams should have different listeners
      assert pid1 != pid2
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      
      # Clean up
      AggregateListener.stop(pid1)
      AggregateListener.stop(pid2)
    end

    test "reuses listener for same stream_id", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      assert {:ok, pid1} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      # Starting with same config should return existing process
      assert {:error, {:already_started, ^pid1}} = AggregateListener.start_link(config)
      
      # Clean up
      AggregateListener.stop(pid1)
    end

    test "returns error with invalid config" do
      # Missing required fields
      assert_raise KeyError, fn ->
        AggregateListener.start_link(%{})
      end
    end
  end

  describe "get_pid/2" do
    test "returns pid for existing listener", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      assert {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      assert AggregateListener.get_pid(store_id, stream_id) == pid
      
      # Clean up
      AggregateListener.stop(pid)
    end

    test "returns nil for non-existent listener", %{store_id: store_id} do
      assert AggregateListener.get_pid(store_id, "non-existent-stream") == nil
    end
  end

  describe "stats/1" do
    test "returns correct stats for listener", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      stats = GenServer.call(pid, :stats)
      
      assert stats.stream_id == stream_id
      assert stats.topic == "#{store_id}:$all"
      assert stats.events_forwarded == 0
      assert stats.events_filtered == 0
      assert stats.subscriber == self()
      
      # Clean up
      AggregateListener.stop(pid)
    end
  end

  describe "event filtering" do
    test "filters events by stream_id and forwards to subscriber", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      # Create mock events with the actual EventRecord structure
      matching_event = %ExESDB.Schema.EventRecord{
        event_stream_id: stream_id,
        event_number: 1,
        event_id: "event-1",
        event_type: "TestEvent",
        data_content_type: 1,
        metadata_content_type: 1,
        data: :erlang.term_to_binary(%{"test" => "data"}),
        metadata: :erlang.term_to_binary(%{"stream_version" => 1}),
        created: System.system_time(:microsecond),
        created_epoch: System.system_time(:millisecond)
      }
      
      non_matching_event = %ExESDB.Schema.EventRecord{
        event_stream_id: "other-stream",
        event_number: 2,
        event_id: "event-2", 
        event_type: "TestEvent",
        data_content_type: 1,
        metadata_content_type: 1,
        data: :erlang.term_to_binary(%{"test" => "data"}),
        metadata: :erlang.term_to_binary(%{"stream_version" => 1}),
        created: System.system_time(:microsecond),
        created_epoch: System.system_time(:millisecond)
      }
      
      # Send events to the listener
      send(pid, {:events, [matching_event, non_matching_event]})
      
      # Should receive the filtered (matching) event
      assert_receive {:events, [filtered_event]}, 1000
      assert filtered_event.stream_id == stream_id
      
      # Verify stats were updated
      stats = GenServer.call(pid, :stats)
      assert stats.events_forwarded == 1
      assert stats.events_filtered == 1  # 1 non-matching event filtered out
      
      # Clean up
      AggregateListener.stop(pid)
    end
    
    test "handles empty event list", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      # Send empty event list
      send(pid, {:events, []})
      
      # Should not receive any events
      refute_receive {:events, _}, 100
      
      # Stats should remain at 0
      stats = GenServer.call(pid, :stats)
      assert stats.events_forwarded == 0
      assert stats.events_filtered == 0
      
      # Clean up
      AggregateListener.stop(pid)
    end
  end

  describe "stop/1" do
    test "stops the listener process", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      assert Process.alive?(pid)
      
      assert :ok = AggregateListener.stop(pid)
      Process.sleep(100) # Allow termination to complete
      refute Process.alive?(pid)
    end
  end

  describe "subscriber monitoring" do
    test "stops when subscriber process dies", %{store_id: store_id, stream_id: stream_id} do
      # Start a temporary subscriber process
      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: subscriber,
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      assert Process.alive?(pid)
      
      # Kill the subscriber process
      Process.exit(subscriber, :kill)
      Process.sleep(100) # Allow listener to handle subscriber death
      
      # Listener should also be dead
      refute Process.alive?(pid)
    end
  end

  describe "topic subscription" do
    test "subscribes to correct PubSub topic", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: self(),
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      stats = GenServer.call(pid, :stats)
      assert stats.topic == "#{store_id}:$all"
      
      # Clean up
      AggregateListener.stop(pid)
    end
  end

  describe "swarm integration" do
    test "registers with swarm using store_id and stream_id", %{store_id: store_id, stream_id: stream_id} do
      config = %{
        store_id: store_id,
        stream_id: stream_id, 
        subscriber: self(),
        replay_historical_events?: false
      }

      {:ok, pid} = AggregateListener.start_link(config)
      Process.sleep(50) # Allow registration to complete
      
      # Should be able to find via get_pid
      assert AggregateListener.get_pid(store_id, stream_id) == pid
      
      # Clean up
      AggregateListener.stop(pid)
      Process.sleep(50) # Allow cleanup
      
      # Should no longer be findable
      assert AggregateListener.get_pid(store_id, stream_id) == nil
    end
  end
end
