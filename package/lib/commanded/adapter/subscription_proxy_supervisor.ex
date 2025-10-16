defmodule ExESDB.Commanded.Adapter.SubscriptionProxySupervisor do
  @moduledoc """
  Supervisor for SubscriptionProxy processes.
  
  This supervisor ensures that SubscriptionProxy processes are restarted
  when they crash, and their PIDs are updated in the ExESDB store.
  
  Each supervisor instance is associated with a specific store_id to support
  multiple stores in umbrella applications.
  """
  
  use Supervisor
  require Logger
  
  alias ExESDB.Commanded.Adapter.SubscriptionProxy
  
  def start_link(opts) do
    store_id = Keyword.get(opts, :store_id, :ex_esdb)
    supervisor_name = supervisor_name(store_id)
    
    Supervisor.start_link(__MODULE__, store_id, name: supervisor_name)
  end
  
  @impl Supervisor
  def init(store_id) do
    Logger.debug("SubscriptionProxySupervisor: Started for store #{store_id}")
    
    children = [
      {DynamicSupervisor, name: proxy_supervisor_name(store_id), strategy: :one_for_one}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  # Helper function to generate store-specific names
  defp supervisor_name(store_id), do: Module.concat(__MODULE__, store_id)
  defp proxy_supervisor_name(store_id), do: Module.concat([__MODULE__, store_id, :ProxySupervisor])
  
  @doc """
  Start a supervised SubscriptionProxy.
  """
  def start_proxy(metadata) do
    store_id = Map.get(metadata, :store, :ex_esdb)
    proxy_sup_name = proxy_supervisor_name(store_id)
    
    child_spec = SubscriptionProxy.child_spec(metadata)
    
    case DynamicSupervisor.start_child(proxy_sup_name, child_spec) do
      {:ok, pid} -> 
        Logger.debug("SubscriptionProxySupervisor: Started proxy #{inspect(pid)}")
        pid
      
      {:error, {:already_started, pid}} -> 
        Logger.debug("SubscriptionProxySupervisor: Proxy already running #{inspect(pid)}")
        pid
      
      {:error, reason} -> 
        Logger.error("SubscriptionProxySupervisor: Failed to start proxy: #{inspect(reason)}")
        throw({:subscription_proxy_start_failed, reason})
    end
  end
  
  @doc """
  Stop a supervised SubscriptionProxy.
  """
  def stop_proxy(store_id, pid) when is_pid(pid) do
    proxy_sup_name = proxy_supervisor_name(store_id)
    DynamicSupervisor.terminate_child(proxy_sup_name, pid)
  end
  
  @doc """
  List all running proxy processes for a specific store.
  """
  def list_proxies(store_id) do
    proxy_sup_name = proxy_supervisor_name(store_id)
    DynamicSupervisor.which_children(proxy_sup_name)
  end
end
