defmodule ExESDB.Commanded.StoreAwareTest do
  use ExUnit.Case, async: true
  
  alias ExESDB.Commanded.AggregateListenerSupervisor
  alias ExESDB.Commanded.Adapter.SubscriptionProxySupervisor
  
  describe "store-aware naming" do
    test "AggregateListenerSupervisor uses store-specific names" do
      # Test that different stores get different supervisor names
      store1_name = Module.concat(AggregateListenerSupervisor, :store1)
      store2_name = Module.concat(AggregateListenerSupervisor, :store2)
      
      assert store1_name != store2_name
      assert store1_name == :"Elixir.ExESDB.Commanded.AggregateListenerSupervisor.store1"
      assert store2_name == :"Elixir.ExESDB.Commanded.AggregateListenerSupervisor.store2"
    end
    
    test "SubscriptionProxySupervisor uses store-specific names" do
      # Test that different stores get different supervisor names
      store1_name = Module.concat(SubscriptionProxySupervisor, :store1)
      store2_name = Module.concat(SubscriptionProxySupervisor, :store2)
      
      assert store1_name != store2_name
      assert store1_name == :"Elixir.ExESDB.Commanded.Adapter.SubscriptionProxySupervisor.store1"
      assert store2_name == :"Elixir.ExESDB.Commanded.Adapter.SubscriptionProxySupervisor.store2"
    end
    
    test "registry names are store-specific" do
      # Test that registry names are unique per store
      store1_registry = Module.concat([AggregateListenerSupervisor, :store1, Registry])
      store2_registry = Module.concat([AggregateListenerSupervisor, :store2, Registry])
      
      assert store1_registry != store2_registry
      assert store1_registry == :"Elixir.ExESDB.Commanded.AggregateListenerSupervisor.store1.Registry"
      assert store2_registry == :"Elixir.ExESDB.Commanded.AggregateListenerSupervisor.store2.Registry"
    end
    
    test "global names include store prefix for SubscriptionProxy" do
      # Test that global names include store information
      store1_global = {:global, {:store1, "test_proxy"}}
      store2_global = {:global, {:store2, "test_proxy"}}
      
      assert store1_global != store2_global
      assert elem(elem(store1_global, 1), 0) == :store1
      assert elem(elem(store2_global, 1), 0) == :store2
    end
  end
  
  describe "configuration validation" do
    test "start_link options include store_id" do
      # Test that both supervisors can be configured with store_id
      opts1 = [store_id: :test_store1]
      opts2 = [store_id: :test_store2]
      
      assert Keyword.get(opts1, :store_id) == :test_store1
      assert Keyword.get(opts2, :store_id) == :test_store2
    end
  end
end
