defmodule ExESDB.Commanded.AdapterIntegrationTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.Commanded.Adapter
  alias ExESDB.Commanded.AggregateListenerSupervisor
  alias ExESDB.Commanded.Adapter.SubscriptionProxySupervisor
  alias ExESDB.Commanded.IntegrationTestHelper
  
  require Logger
  
  @moduletag :integration
  @moduletag timeout: 120_000
  
  @store_id :integration_test_store
  @stream_prefix "integration_test_"
  @test_stream_id "test_aggregate_123"
  @full_stream_id @stream_prefix <> @test_stream_id
  
  # Test configuration
  @adapter_config %{
    store_id: @store_id,
    stream_prefix: @stream_prefix,
    serializer: Jason,
    application: :ex_esdb_commanded
  }
  
  setup_all do
    # Clean up any existing test data
    IntegrationTestHelper.cleanup_test_data(@store_id)
    
    # Start ExESDB.System
    Logger.info("Starting ExESDB.System for integration test")
    {:ok, _} = IntegrationTestHelper.start_exesdb_system(@store_id)
    
    # Start adapter supervisors
    {:ok, aggregate_sup} = AggregateListenerSupervisor.start_link(store_id: @store_id)
    {:ok, subscription_sup} = SubscriptionProxySupervisor.start_link(store_id: @store_id)
    
    on_exit(fn ->
      GenServer.stop(aggregate_sup)
      GenServer.stop(subscription_sup)
      IntegrationTestHelper.stop_exesdb_system(@store_id)
      IntegrationTestHelper.cleanup_test_data(@store_id)
    end)
    
    {:ok, %{
      aggregate_sup: aggregate_sup,
      subscription_sup: subscription_sup
    }}
  end
  
  describe "ExESDB Commanded Adapter Integration" do
    test "GIVEN ExESDB.System is running WHEN appending events via adapter THEN system should not timeout", %{
      aggregate_sup: aggregate_sup,
      subscription_sup: subscription_sup
    } do
      # Verify supervisors are alive
      assert Process.alive?(aggregate_sup)
      assert Process.alive?(subscription_sup)
      
      # Create test events
      events = IntegrationTestHelper.create_test_events(5)
      
      # Append events to stream
      result = Adapter.append_to_stream(
        @adapter_config,
        @test_stream_id,
        :any_version,
        events,
        []
      )
      
      # Verify append succeeded
      assert result == :ok
      
      # Wait for events to be persisted
      Process.sleep(1_000)
      
      Logger.info("Successfully appended #{length(events)} events to stream #{@full_stream_id}")
    end
    
    test "GIVEN events are appended WHEN streaming forward THEN events should be retrieved", %{
      aggregate_sup: aggregate_sup,
      subscription_sup: subscription_sup
    } do
      # Verify supervisors are alive
      assert Process.alive?(aggregate_sup)
      assert Process.alive?(subscription_sup)
      
      # Create and append test events
      events = IntegrationTestHelper.create_test_events(3)
      
      :ok = Adapter.append_to_stream(
        @adapter_config,
        @test_stream_id,
        :any_version,
        events,
        []
      )
      
      # Wait for events to be persisted
      Process.sleep(1_000)
      
      # Stream events forward
      stream_result = Adapter.stream_forward(
        @adapter_config,
        @test_stream_id,
        0,
        100
      )
      
      # Verify we can retrieve events
      assert {:ok, recorded_events} = stream_result
      assert length(recorded_events) >= length(events)
      
      # Verify event structure
      first_event = List.first(recorded_events)
      assert %Commanded.EventStore.RecordedEvent{} = first_event
      assert first_event.stream_id == @full_stream_id
      assert first_event.stream_version >= 0
      
      Logger.info("Successfully streamed #{length(recorded_events)} events from stream #{@full_stream_id}")
    end
    
    test "GIVEN events are appended WHEN ExESDB.System is restarted THEN events must be retrievable", %{
      aggregate_sup: aggregate_sup,
      subscription_sup: subscription_sup
    } do
      # Verify supervisors are alive
      assert Process.alive?(aggregate_sup)
      assert Process.alive?(subscription_sup)
      
      # Create and append test events before restart
      events_before_restart = IntegrationTestHelper.create_test_events(3, "before_restart")
      
      :ok = Adapter.append_to_stream(
        @adapter_config,
        @test_stream_id,
        :any_version,
        events_before_restart,
        []
      )
      
      # Wait for events to be persisted
      Process.sleep(1_000)
      
      # Restart ExESDB.System
      Logger.info("Restarting ExESDB.System")
      IntegrationTestHelper.stop_exesdb_system(@store_id)
      Process.sleep(2_000)
      
      {:ok, _} = IntegrationTestHelper.start_exesdb_system(@store_id)
      
      # Verify events are still retrievable after restart
      stream_result = Adapter.stream_forward(
        @adapter_config,
        @test_stream_id,
        0,
        100
      )
      
      assert {:ok, recorded_events} = stream_result
      assert length(recorded_events) >= length(events_before_restart)
      
      # Verify we can still append new events after restart
      events_after_restart = IntegrationTestHelper.create_test_events(2, "after_restart")
      
      :ok = Adapter.append_to_stream(
        @adapter_config,
        @test_stream_id,
        :stream_exists,
        events_after_restart,
        []
      )
      
      # Wait for new events to be persisted
      Process.sleep(1_000)
      
      # Stream all events
      {:ok, all_events} = Adapter.stream_forward(
        @adapter_config,
        @test_stream_id,
        0,
        100
      )
      
      # Verify total count
      total_expected = length(events_before_restart) + length(events_after_restart)
      assert length(all_events) >= total_expected
      
      Logger.info("Successfully retrieved #{length(all_events)} events after system restart")
    end
    
    test "GIVEN multiple streams WHEN appending concurrently THEN all events should be persisted", %{
      aggregate_sup: aggregate_sup,
      subscription_sup: subscription_sup
    } do
      # Verify supervisors are alive
      assert Process.alive?(aggregate_sup)
      assert Process.alive?(subscription_sup)
      
      # Create multiple streams concurrently
      stream_tasks = for i <- 1..5 do
        Task.async(fn ->
          stream_id = "concurrent_stream_#{i}"
          events = IntegrationTestHelper.create_test_events(3, "concurrent_#{i}")
          
          result = Adapter.append_to_stream(
            @adapter_config,
            stream_id,
            :any_version,
            events,
            []
          )
          
          {stream_id, result, length(events)}
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(stream_tasks, 30_000)
      
      # Verify all appends succeeded
      Enum.each(results, fn {stream_id, result, event_count} ->
        assert result == :ok
        Logger.info("Successfully appended #{event_count} events to stream #{stream_id}")
      end)
      
      # Wait for all events to be persisted
      Process.sleep(2_000)
      
      # Verify each stream can be read back
      Enum.each(results, fn {stream_id, _result, expected_count} ->
        {:ok, recorded_events} = Adapter.stream_forward(
          @adapter_config,
          stream_id,
          0,
          100
        )
        
        assert length(recorded_events) >= expected_count
        Logger.info("Successfully read #{length(recorded_events)} events from stream #{stream_id}")
      end)
    end
    
    test "GIVEN large event payloads WHEN appending THEN system should handle gracefully", %{
      aggregate_sup: aggregate_sup,
      subscription_sup: subscription_sup
    } do
      # Verify supervisors are alive
      assert Process.alive?(aggregate_sup)
      assert Process.alive?(subscription_sup)
      
      # Create events with large payloads
      large_events = IntegrationTestHelper.create_large_test_events(2)
      
      # Append large events
      result = Adapter.append_to_stream(
        @adapter_config,
        "large_payload_stream",
        :any_version,
        large_events,
        []
      )
      
      assert result == :ok
      
      # Wait for events to be persisted
      Process.sleep(2_000)
      
      # Verify events can be retrieved
      {:ok, recorded_events} = Adapter.stream_forward(
        @adapter_config,
        "large_payload_stream",
        0,
        100
      )
      
      assert length(recorded_events) >= length(large_events)
      
      # Verify event data integrity
      first_event = List.first(recorded_events)
      assert byte_size(first_event.data) > 1000
      
      Logger.info("Successfully handled large event payloads")
    end
  end
  
end
