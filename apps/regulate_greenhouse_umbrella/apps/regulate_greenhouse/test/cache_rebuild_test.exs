defmodule RegulateGreenhouse.CacheRebuildTest do
  use ExUnit.Case, async: false
  
  alias RegulateGreenhouse.{API, CacheService, CacheRebuildService}
  
  require Logger
  
  @moduletag :integration
  
  setup do
    # Clear cache before each test
    CacheService.clear_cache()
    
    # Wait a bit for cache to be cleared
    :timer.sleep(100)
    
    :ok
  end
  
  describe "cache rebuild functionality" do
    @tag :skip  # Skip by default since it requires ExESDB running
    test "rebuild_cache_info provides accurate statistics" do
      # Get rebuild info when cache is empty
      {:ok, info} = CacheRebuildService.get_rebuild_info()
      
      Logger.info("Rebuild info: #{inspect(info)}")
      
      assert is_map(info)
      assert Map.has_key?(info, :total_streams)
      assert Map.has_key?(info, :total_events)
      assert Map.has_key?(info, :current_cache_size)
      assert Map.has_key?(info, :estimated_rebuild_time_ms)
      assert Map.has_key?(info, :streams)
      
      # Cache should be empty initially
      assert info.current_cache_size == 0
    end
    
    @tag :skip  # Skip by default since it requires ExESDB running  
    test "rebuild_cache reconstructs cache from events" do
      # First, create some test data
      greenhouse_id = "test_greenhouse_#{:rand.uniform(1000)}"
      
      # Create a greenhouse
      :ok = API.create_greenhouse(greenhouse_id, "Test Greenhouse", "Test Location")
      
      # Wait for event processing
      :timer.sleep(1000)
      
      # Verify greenhouse is in cache
      {:ok, greenhouse} = CacheService.get_greenhouse(greenhouse_id)
      assert greenhouse != nil
      assert greenhouse.greenhouse_id == greenhouse_id
      
      # Clear the cache to simulate restart
      CacheService.clear_cache()
      
      # Verify cache is empty
      {:ok, nil} = CacheService.get_greenhouse(greenhouse_id)
      assert CacheService.count_greenhouses() == 0
      
      # Now rebuild cache from events
      {:ok, stats} = CacheRebuildService.rebuild_cache()
      
      Logger.info("Rebuild stats: #{inspect(stats)}")
      
      # Verify stats
      assert stats.events_processed > 0
      assert stats.greenhouses_created >= 1
      assert stats.duration_ms > 0
      assert stats.cache_size > 0
      
      # Verify greenhouse is back in cache
      {:ok, rebuilt_greenhouse} = CacheService.get_greenhouse(greenhouse_id)
      assert rebuilt_greenhouse != nil
      assert rebuilt_greenhouse.greenhouse_id == greenhouse_id
      assert rebuilt_greenhouse.name == "Test Greenhouse"
      assert rebuilt_greenhouse.location == "Test Location"
    end
    
    @tag :skip  # Skip by default since it requires ExESDB running
    test "partial cache rebuild works for specific streams" do
      # Create multiple greenhouses
      greenhouse1 = "test_greenhouse_1_#{:rand.uniform(1000)}"
      greenhouse2 = "test_greenhouse_2_#{:rand.uniform(1000)}"
      
      # Create greenhouses
      :ok = API.create_greenhouse(greenhouse1, "Test Greenhouse 1", "Location 1")
      :ok = API.create_greenhouse(greenhouse2, "Test Greenhouse 2", "Location 2")
      
      # Wait for processing
      :timer.sleep(1000)
      
      # Clear cache
      CacheService.clear_cache()
      
      # Rebuild cache for only one stream
      stream_id = "regulate_greenhouse_#{greenhouse1}"
      {:ok, stats} = CacheRebuildService.rebuild_cache_for_streams([stream_id])
      
      Logger.info("Partial rebuild stats: #{inspect(stats)}")
      
      # Verify only one greenhouse was rebuilt
      assert stats.greenhouses_created == 1
      assert stats.streams_processed == 1
      
      # Verify correct greenhouse is in cache
      {:ok, rebuilt_greenhouse} = CacheService.get_greenhouse(greenhouse1)
      assert rebuilt_greenhouse != nil
      
      # Verify other greenhouse is not in cache
      {:ok, nil} = CacheService.get_greenhouse(greenhouse2)
    end
  end
  
  describe "error handling" do
    test "get_rebuild_info handles no streams gracefully" do
      # This test should work even without ExESDB running
      case CacheRebuildService.get_rebuild_info() do
        {:ok, info} ->
          # If ExESDB is running, we should get valid info
          assert is_map(info)
          
        {:error, reason} ->
          # If ExESDB is not running, we should get an error
          Logger.info("Expected error when ExESDB not running: #{inspect(reason)}")
          assert is_tuple(reason) or is_atom(reason)
      end
    end
  end
end
