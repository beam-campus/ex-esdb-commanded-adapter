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

    test "starts different listeners for different streams" do
      config1 = %{
        store_id: @store_id,
        stream_id: "stream-1",
        subscriber: self()
      }
      
      config2 = %{
        store_id: @store_id,
        stream_id: "stream-2",
        subscriber: self()
      }

      assert {:ok, pid1} = AggregateListenerSupervisor.start_listener(config1)
      Process.sleep(50) # Allow registration to complete
      assert {:ok, pid2} = AggregateListenerSupervisor.start_listener(config2)
      Process.sleep(50) # Allow registration to complete
      
      # Different streams should have different listeners
      assert pid1 != pid2
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
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
      
      assert :ok = AggregateListenerSupervisor.stop_listener(@store_id, @stream_id)
      refute Process.alive?(pid)
    end

    test "returns ok for non-existent listener" do
      assert :ok = AggregateListenerSupervisor.stop_listener(@store_id, "non-existent-stream")
    end
  end

  describe "stop_listeners_for_stream/2" do
    test "stops all listeners for a given stream", %{registry: registry} do
      stream_id = "shared-stream-456"
      
      # Start multiple listeners - they should all reuse the same process
      pids = for i <- 1..3 do
        subscriber = spawn(fn -> Process.sleep(:infinity) end)
        config = %{
          store_id: @store_id,
          stream_id: stream_id,
          subscriber: subscriber
        }
        {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
        pid
      end
      
      # All PIDs should be the same (reused listener)
      assert Enum.uniq(pids) |> length() == 1
      [shared_pid] = Enum.uniq(pids)

      Process.sleep(100) # Allow registration to complete
      
      # Stop all listeners for the stream
      :ok = AggregateListenerSupervisor.stop_listeners_for_stream(@store_id, stream_id)
      
      Process.sleep(100) # Allow termination to complete
      
      # Verify the shared process is dead
      refute Process.alive?(shared_pid)
    end
  end

  describe "stats/1" do
    test "returns correct statistics for active listeners" do
      # Start multiple listeners with unique streams - each should have its own listener process
      _pids = for i <- 1..3 do
        config = %{
          store_id: @store_id,
          stream_id: "stream-#{i}",
          subscriber: spawn(fn -> Process.sleep(:infinity) end)
        }
        {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
        pid
      end

      Process.sleep(100) # Allow registration to complete
      
      # Verify stats - should have 3 listeners (one per stream)
      stats = AggregateListenerSupervisor.stats(@store_id)
      assert stats.total_listeners == 3
      assert stats.listeners_by_store[@store_id] == 3
      # Should have 3 different streams
      assert length(stats.active_streams) == 3
      assert Enum.sort(stats.active_streams) == ["stream-1", "stream-2", "stream-3"]
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
      # Start multiple listeners - each should have its own process
      pids = for i <- 1..3 do
        stream_id = "stream-#{i}"
        subscriber = self()
        config = %{
          store_id: @store_id,
          stream_id: stream_id,
          subscriber: subscriber
        }
        {:ok, pid} = AggregateListenerSupervisor.start_listener(config)
        pid
      end
      
      # All PIDs should be different (separate listeners per stream)
      assert Enum.uniq(pids) |> length() == 3

      Process.sleep(100) # Allow registration to complete
      
      # Get current listeners - should be 3
      listeners = AggregateListenerSupervisor.list_listeners(@store_id)
      
      # Should have exactly 3 listeners (one per stream)
      assert length(listeners) == 3
      
      # Verify each listener has the correct stream_id and is alive
      stream_ids = Enum.map(listeners, & &1.stream_id) |> Enum.sort()
      assert stream_ids == ["stream-1", "stream-2", "stream-3"]
      
      for listener <- listeners do
        assert listener.store_id == @store_id
        assert listener.subscriber == self()
        assert Process.alive?(listener.listener_pid)
      end
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
