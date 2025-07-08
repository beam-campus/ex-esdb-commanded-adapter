defmodule ExESDB.Commanded.Adapter.SubscriptionProxySupervisor do
  @moduledoc """
  Supervisor for SubscriptionProxy processes.
  
  This supervisor ensures that SubscriptionProxy processes are restarted
  when they crash, and their PIDs are updated in the ExESDB store.
  """
  
  use DynamicSupervisor
  require Logger
  
  alias ExESDB.Commanded.Adapter.SubscriptionProxy
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  @doc """
  Start a supervised SubscriptionProxy.
  """
  def start_proxy(metadata) do
    child_spec = SubscriptionProxy.child_spec(metadata)
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> 
        Logger.info("SubscriptionProxySupervisor: Started supervised proxy #{inspect(pid)}")
        pid
      
      {:error, {:already_started, pid}} -> 
        Logger.info("SubscriptionProxySupervisor: Proxy already running #{inspect(pid)}")
        pid
      
      {:error, reason} -> 
        Logger.error("SubscriptionProxySupervisor: Failed to start proxy: #{inspect(reason)}")
        throw({:subscription_proxy_start_failed, reason})
    end
  end
  
  @doc """
  Stop a supervised SubscriptionProxy.
  """
  def stop_proxy(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
  
  @doc """
  List all running proxy processes.
  """
  def list_proxies do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
