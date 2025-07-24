defmodule ExESDB.Commanded.MultiStoreIntegrationTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.Commanded.AggregateListenerSupervisor
  alias ExESDB.Commanded.Adapter.SubscriptionProxySupervisor
  
  @moduletag :integration
  
  describe "multi-store integration" do
    test "can start multiple AggregateListenerSupervisors with different store_ids" do
      # Start supervisors for different stores
      {:ok, accounts_sup} = AggregateListenerSupervisor.start_link([store_id: :accounts])
      {:ok, payments_sup} = AggregateListenerSupervisor.start_link([store_id: :payments])
      
      # Verify they are different processes
      assert accounts_sup != payments_sup
      
      # Verify they have different names
      accounts_name = Module.concat(AggregateListenerSupervisor, :accounts)
      payments_name = Module.concat(AggregateListenerSupervisor, :payments)
      
      assert Process.whereis(accounts_name) == accounts_sup
      assert Process.whereis(payments_name) == payments_sup
      
      # Clean up
      GenServer.stop(accounts_sup)
      GenServer.stop(payments_sup)
    end
    
    test "can start multiple SubscriptionProxySupervisors with different store_ids" do
      # Start supervisors for different stores
      {:ok, accounts_sup} = SubscriptionProxySupervisor.start_link([store_id: :accounts])
      {:ok, payments_sup} = SubscriptionProxySupervisor.start_link([store_id: :payments])
      
      # Verify they are different processes
      assert accounts_sup != payments_sup
      
      # Verify they have different names
      accounts_name = Module.concat(SubscriptionProxySupervisor, :accounts)
      payments_name = Module.concat(SubscriptionProxySupervisor, :payments)
      
      assert Process.whereis(accounts_name) == accounts_sup
      assert Process.whereis(payments_name) == payments_sup
      
      # Clean up
      GenServer.stop(accounts_sup)
      GenServer.stop(payments_sup)
    end
    
    test "store-specific APIs work correctly" do
      # Start supervisors for different stores
      {:ok, accounts_sup} = AggregateListenerSupervisor.start_link([store_id: :accounts])
      {:ok, payments_sup} = AggregateListenerSupervisor.start_link([store_id: :payments])
      
      # Test that stats are store-specific
      accounts_stats = AggregateListenerSupervisor.stats(:accounts)
      payments_stats = AggregateListenerSupervisor.stats(:payments)
      
      assert accounts_stats.total_listeners == 0
      assert payments_stats.total_listeners == 0
      
      # Test that list_listeners are store-specific
      accounts_listeners = AggregateListenerSupervisor.list_listeners(:accounts)
      payments_listeners = AggregateListenerSupervisor.list_listeners(:payments)
      
      assert accounts_listeners == []
      assert payments_listeners == []
      
      # Clean up
      GenServer.stop(accounts_sup)
      GenServer.stop(payments_sup)
    end
  end
end
