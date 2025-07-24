defmodule ExESDB.Commanded.Adapter.SubscriptionProxySupervisor do
  @moduledoc """
  Supervisor for SubscriptionProxy processes.
  
  This supervisor ensures that SubscriptionProxy processes are restarted
  when they crash, and their PIDs are updated in the ExESDB store.
  
  Each supervisor instance is associated with a specific store_id to support
  multiple stores in umbrella applications.
  """
  
  use DynamicSupervisor
  require Logger
  
  alias ExESDB.Commanded.Adapter.SubscriptionProxy
  
  def start_link(opts) do
    store_id = Keyword.get(opts, :store_id, :ex_esdb)
    supervisor_name = supervisor_name(store_id)
    
    DynamicSupervisor.start_link(__MODULE__, store_id, name: supervisor_name)
  end
  
  @impl DynamicSupervisor
  def init(store_id) do
    Logger.info("SubscriptionProxySupervisor: Started for store #{store_id}")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  # Helper function to generate store-specific names
  defp supervisor_name(store_id), do: Module.concat(__MODULE__, store_id)
  
  @doc """
  Start a supervised SubscriptionProxy.
  """
  def start_proxy(metadata) do
    store_id = Map.get(metadata, :store, :ex_esdb)
    supervisor_name = supervisor_name(store_id)
    
    child_spec = SubscriptionProxy.child_spec(metadata)
    
    case DynamicSupervisor.start_child(supervisor_name, child_spec) do
      {:ok, pid} -> 
        Logger.info("SubscriptionProxySupervisor: Started supervised proxy #{inspect(pid)} (store: #{store_id})")
        pid
      
      {:error, {:already_started, pid}} -> 
        Logger.info("SubscriptionProxySupervisor: Proxy already running #{inspect(pid)} (store: #{store_id})")
        pid
      
      {:error, reason} -> 
        Logger.error("SubscriptionProxySupervisor: Failed to start proxy: #{inspect(reason)} (store: #{store_id})")
        throw({:subscription_proxy_start_failed, reason})
    end
  end
  
  @doc """
  Stop a supervised SubscriptionProxy.
  """
  def stop_proxy(store_id, pid) when is_pid(pid) do
    supervisor_name = supervisor_name(store_id)
    DynamicSupervisor.terminate_child(supervisor_name, pid)
  end
  
  @doc """
  List all running proxy processes for a specific store.
  """
  def list_proxies(store_id) do
    supervisor_name = supervisor_name(store_id)
    DynamicSupervisor.which_children(supervisor_name)
  end
end
