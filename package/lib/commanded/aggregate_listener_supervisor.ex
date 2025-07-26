defmodule ExESDB.Commanded.AggregateListenerSupervisor do
  @moduledoc """
  DynamicSupervisor for managing AggregateListener processes.

  Uses Swarm for distributed process registration. Each supervisor is uniquely
  identified by a combination of store_id and node().
  """

  use DynamicSupervisor
  require Logger

  alias ExESDB.Commanded.AggregateListener
  alias ExESDB.Commanded.Themes

  def hash_key(store_id),
    do: Integer.to_string(:erlang.phash2({store_id, node()}))

  def swarm_key(store_id),
    do: {:aggregate_listener_supervisor, hash_key(store_id)}

  def start_link(opts) do
    store_id = Keyword.get(opts, :store_id, :undefined)

    DynamicSupervisor.start_link(
      __MODULE__,
      store_id,
      name: Module.concat(__MODULE__, hash_key(store_id))
    )
  end

  @impl DynamicSupervisor
  def init(store_id) do
    Logger.info("AggregateListenerSupervisor: Started for store #{store_id} on node #{node()}")
    Swarm.register_name(swarm_key(store_id), self())

    res =
      DynamicSupervisor.init(
        strategy: :one_for_one,
        restart: :temporary
      )

    IO.puts(Themes.aggregate_listener_supervisor(self(), "is UP!"))
    res
  end

  @spec do_start_listener(pid(), map()) :: {:ok, pid()} | {:error, term()}
  defp do_start_listener(supervisor_pid, config) do
    store_id = Map.fetch!(config, :store_id)
    child_spec = {AggregateListener, config}

    case DynamicSupervisor.start_child(supervisor_pid, child_spec) do
      {:ok, child_pid} ->
        Logger.info(
          "AggregateListenerSupervisor: Started listener #{inspect(child_pid)} for store '#{store_id}'"
        )

        {:ok, child_pid}

      {:error, {:already_started, child_pid}} ->
        {:ok, child_pid}

      {:error, reason} ->
        Logger.error(
          "AggregateListenerSupervisor: Failed to start listener for stream '#{config.stream_id}' (store: #{config.store_id}): #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp do_stop_listener(supervisor_pid, store_id) do
    child_pid = AggregateListener.get_pid(store_id)

    case DynamicSupervisor.terminate_child(supervisor_pid, child_pid) do
      :ok ->
        Logger.debug(
          "AggregateListenerSupervisor: Stopped listener #{inspect(child_pid)} (store: #{store_id})"
        )

        :ok

      {:error, :not_found} ->
        Logger.debug(
          "AggregateListenerSupervisor: Listener #{inspect(child_pid)} not found (store: #{store_id})"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "AggregateListenerSupervisor: Failed to stop listener #{inspect(child_pid)}: #{inspect(reason)} (store: #{store_id})"
        )

        :ok
    end
  end

  @doc """
  Starts a new AggregateListener under supervision.

  Returns the PID of the started listener or an error.
  """
  @spec start_listener(map()) :: {:ok, pid()} | {:error, term()}
  def start_listener(config) do
    store_id = Map.fetch!(config, :store_id)
    supervisor_name = swarm_key(store_id)
    # Get supervisor PID via Swarm
    case Swarm.whereis_name(supervisor_name) do
      :undefined ->
        Logger.error(
          "AggregateListenerSupervisor: No supervisor found for store #{store_id} on node #{node()}"
        )

        {:error, :no_supervisor}

      supervisor_pid when is_pid(supervisor_pid) ->
        do_start_listener(supervisor_pid, config)
    end
  end

  @doc """
  Stops a specific AggregateListener.
  """
  @spec stop_listener(atom(), pid()) :: :ok
  def stop_listener(store_id, pid) when is_pid(pid) do
    supervisor_name = swarm_key(store_id)

    case Swarm.whereis_name(supervisor_name) do
      :undefined ->
        Logger.warning(
          "AggregateListenerSupervisor: No supervisor found for store #{store_id} on node #{node()}"
        )

        :ok

      supervisor_pid when is_pid(supervisor_pid) ->
        do_stop_listener(supervisor_pid, store_id)
    end
  end
end
