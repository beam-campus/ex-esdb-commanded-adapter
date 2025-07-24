defmodule ExESDB.Commanded.IntegrationTestHelper do
  @moduledoc """
  Helper functions for integration tests.
  """
  
  require Logger
  import ExUnit.Assertions
  
  @doc """
  Starts ExESDB.System with test configuration.
  """
  def start_exesdb_system(store_id \\ :test_store) do
    config = [
      store_id: store_id,
      data_dir: "/tmp/exesdb_test_#{store_id}",
      node_id: "test_node_#{store_id}",
      cluster_size: 1,
      port: 2113 + :rand.uniform(1000),
      http_port: 2114 + :rand.uniform(1000),
      pub_sub: :ex_esdb_pubsub
    ]
    
    case ExESDB.System.start_link(config) do
      {:ok, pid} ->
        # Wait for system to be ready
        wait_for_system_ready(store_id)
        {:ok, pid}
      
      {:error, {:already_started, pid}} ->
        {:ok, pid}
        
      error ->
        error
    end
  end
  
  @doc """
  Stops ExESDB.System gracefully.
  """
  def stop_exesdb_system(store_id \\ :test_store) do
    case Process.whereis(ExESDB.System.system_name(store_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 10_000)
    end
  end
  
  @doc """
  Waits for ExESDB.System to be ready for operations.
  """
  def wait_for_system_ready(store_id, timeout \\ 30_000) do
    wait_until(fn ->
      try do
        # Try to call a simple API function to check if system is ready
        ExESDBGater.API.list_stores()
        true
      rescue
        _ -> false
      end
    end, timeout, 100)
  end
  
  @doc """
  Creates test events with specified count and suffix.
  """
  def create_test_events(count, suffix \\ "test") do
    for i <- 1..count do
      %Commanded.EventStore.EventData{
        event_type: "TestEvent#{suffix}",
        data: %{
          id: i,
          name: "Test Event #{i} #{suffix}",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          value: :rand.uniform(1000),
          test_metadata: %{
            user_id: "test_user_#{i}"
          }
        },
        metadata: %{
          created_at: DateTime.utc_now()
        },
        correlation_id: UUID.uuid4(),
        causation_id: UUID.uuid4()
      }
    end
  end
  
  @doc """
  Creates test events with large payloads.
  """
  def create_large_test_events(count) do
    # Create events with large payloads (>1KB each)
    large_data = String.duplicate("A", 1500)
    
    for i <- 1..count do
      %Commanded.EventStore.EventData{
        event_type: "LargeTestEvent",
        data: %{
          id: i,
          large_field: large_data,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          additional_data: %{
            field_1: String.duplicate("X", 500),
            field_2: String.duplicate("Y", 500),
            field_3: String.duplicate("Z", 500)
          }
        },
        metadata: %{
          created_at: DateTime.utc_now()
        },
        correlation_id: UUID.uuid4(),
        causation_id: UUID.uuid4()
      }
    end
  end
  
  @doc """
  Cleans up test data directory.
  """
  def cleanup_test_data(store_id \\ :test_store) do
    data_dir = "/tmp/exesdb_test_#{store_id}"
    File.rm_rf(data_dir)
  end
  
  @doc """
  Waits until a condition is met or timeout occurs.
  """
  def wait_until(condition_fn, timeout \\ 30_000, interval \\ 100) do
    start_time = System.monotonic_time(:millisecond)
    
    do_wait_until(condition_fn, start_time, timeout, interval)
  end
  
  defp do_wait_until(condition_fn, start_time, timeout, interval) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time - start_time > timeout do
      raise "Timeout waiting for condition"
    end
    
    if condition_fn.() do
      :ok
    else
      Process.sleep(interval)
      do_wait_until(condition_fn, start_time, timeout, interval)
    end
  end
  
  @doc """
  Verifies that recorded events match expected structure.
  """
  def verify_recorded_events(recorded_events, expected_count \\ nil) do
    if expected_count do
      assert length(recorded_events) >= expected_count
    end
    
    Enum.each(recorded_events, fn event ->
      assert %Commanded.EventStore.RecordedEvent{} = event
      assert is_binary(event.stream_id)
      assert is_integer(event.stream_version)
      assert is_binary(event.event_id)
      assert is_binary(event.event_type)
      assert is_map(event.data)
      assert is_map(event.metadata)
      assert %DateTime{} = event.created_at
    end)
    
    recorded_events
  end
end
