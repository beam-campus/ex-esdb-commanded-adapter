defmodule ExESDB.Commanded.AggregateListenerSupervisorTest do
  use ExUnit.Case, async: true
  require Logger

  alias ExESDB.Commanded.AggregateListenerSupervisor

  @store_id :test_store
  @stream_id "test-stream-123"

  setup do
    registry_name = Module.concat([AggregateListenerSupervisor, @store_id, Registry])
    start_supervised!({Registry, keys: :unique, name: registry_name})
    supervisor = start_supervised!({AggregateListenerSupervisor, store_id: @store_id})
    %{supervisor: supervisor, registry: registry_name}
  end

  describe "start_listener/1" do
    test "starts a new listener with valid config" do
      config = %{
        store_id: @store_id,
        stream_id: @stream_id,
        subscriber: self()
      }

      assert {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
      Process.sleep(50) # Allow registration to complete
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "reuses existing listener for same stream and subscriber" do
      config = %{
        store_id: @store_id,
        stream_id: @stream_id,
        subscriber: self()
      }

      assert {:ok, pid1} = AggregateListenerSupervisor.start_listener(config)
      Process.sleep(50) # Allow registration to complete
      assert {:ok, pid2} = AggregateListenerSupervisor.start_listener(config)
      assert pid1 == pid2
    end

    test "starts new listener when previous one died" do
      config = %{
        store_id: @store_id,
        stream_id: @stream_id,
        subscriber: self()
      }

      assert {:ok, pid1} = AggregateListenerSupervisor.start_listener(config)
      Process.sleep(50) # Allow registration to complete
      Process.exit(pid1, :kill)
      Process.sleep(100) # Allow supervisor to handle exit
      assert {:ok, pid2} = AggregateListenerSupervisor.start_listener(config)
      Process.sleep(50) # Allow registration to complete
      assert pid1 != pid2
      assert Process.alive?(pid2)
    end

    test "returns error with invalid config" do
      # Missing required fields
      assert_raise KeyError, fn ->
        AggregateListenerSupervisor.start_listener(%{})
      end
    end
  end

  describe "stop_listener/2" do
    test "stops a running listener" do
      config = %{
        store_id: @store_id,
        stream_id: @stream_id,
        subscriber: self()
      }

      {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
      assert Process.alive?(pid)
      
      assert :ok = AggregateListenerSupervisor.stop_listener(@store_id, pid)
      refute Process.alive?(pid)
    end

    test "returns ok for non-existent listener" do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)
      assert :ok = AggregateListenerSupervisor.stop_listener(@store_id, non_existent_pid)
    end
  end

  describe "stop_listeners_for_stream/2" do
    test "stops all listeners for a given stream", %{registry: registry} do
      stream_id = "shared-stream-456"
      listeners = []
      
      # Start three listeners with unique subscribers
      listeners =
        for i <- 1..3 do
          subscriber = spawn(fn -> Process.sleep(:infinity) end)
          config = %{
            store_id: @store_id,
            stream_id: stream_id,
            subscriber: subscriber
          }
          {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
          pid
        end

      Process.sleep(100) # Allow registration to complete
      
      # Stop all listeners for the stream
      :ok = AggregateListenerSupervisor.stop_listeners_for_stream(@store_id, stream_id)
      
      Process.sleep(100) # Allow termination to complete
      
      # Verify all processes are dead
      for pid <- listeners do
        refute Process.alive?(pid)
      end
    end
  end

  describe "stats/1" do
    test "returns correct statistics for active listeners" do
      # Start multiple listeners with unique streams
      for i <- 1..3 do
        config = %{
          store_id: @store_id,
          stream_id: "stream-#{i}",
          subscriber: spawn(fn -> Process.sleep(:infinity) end)
        }
        {:ok, _pid} = AggregateListenerSupervisor.start_listener(config)
      end

      Process.sleep(100) # Allow registration to complete
      
      # Verify stats
      stats = AggregateListenerSupervisor.stats(@store_id)
      assert stats.total_listeners == 3
      assert stats.listeners_by_store[@store_id] == 3
      assert length(stats.active_streams) == 3
      assert stats.active_streams |> Enum.sort() == ["stream-1", "stream-2", "stream-3"] |> Enum.sort()
    end

    test "returns empty statistics when no listeners are active" do
      stats = AggregateListenerSupervisor.stats(@store_id)
      
      assert stats.total_listeners == 0
      assert map_size(stats.listeners_by_store) == 0
      assert stats.active_streams == []
    end
  end

  describe "list_listeners/1" do
    test "returns details of all active listeners" do
      expected_listeners = for i <- 1..3 do
        stream_id = "stream-#{i}"
        subscriber = self()
        config = %{
          store_id: @store_id,
          stream_id: stream_id,
          subscriber: subscriber
        }
        {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
        %{
          store_id: @store_id,
          stream_id: stream_id,
          subscriber: subscriber,
          listener_pid: pid
        }
      end

      Process.sleep(100) # Allow registration to complete
      
      # Get current listeners
      listeners = AggregateListenerSupervisor.list_listeners(@store_id)
      
      # Sort both lists by stream_id for comparison
      sorted_expected = Enum.sort_by(expected_listeners, & &1.stream_id)
      sorted_actual = Enum.sort_by(listeners, & &1.stream_id)
      
      # Compare all fields
      assert length(sorted_actual) == length(sorted_expected)
      
      Enum.zip(sorted_actual, sorted_expected) |> Enum.each(fn {actual, expected} ->
        assert actual.store_id == expected.store_id
        assert actual.stream_id == expected.stream_id
        assert actual.subscriber == expected.subscriber
        assert Process.alive?(actual.listener_pid)
      end)
    end

    test "returns empty list when no listeners are active" do
      assert AggregateListenerSupervisor.list_listeners(@store_id) == []
    end
  end

  # Helper Functions

  defp wait_for_process_death(pid) do
    ref = Process.monitor(pid)
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      1000 -> raise "Process did not die within timeout"
    end
  end
end
