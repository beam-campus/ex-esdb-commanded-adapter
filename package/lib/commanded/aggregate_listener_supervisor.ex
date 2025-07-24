defmodule ExESDB.Commanded.AggregateListenerSupervisor do
  @moduledoc """
  DynamicSupervisor for managing AggregateListener processes.

  This supervisor is responsible for:
  1. Starting and stopping AggregateListener processes
  2. Ensuring proper supervision and restart strategies
  3. Maintaining a registry of active listeners
  4. Cleanup on application shutdown

  Each supervisor instance is associated with a specific store_id to support
  multiple stores in umbrella applications.
  """

  use DynamicSupervisor
  require Logger

  alias ExESDB.Commanded.AggregateListener

  def start_link(opts) do
    store_id = Keyword.get(opts, :store_id, :ex_esdb)
    supervisor_name = supervisor_name(store_id)
    registry_name = registry_name(store_id)

    DynamicSupervisor.start_link(__MODULE__, {store_id, registry_name}, name: supervisor_name)
  end

  @impl DynamicSupervisor
  def init({store_id, registry_name}) do
    # Start the registry for tracking listeners for this store
    Registry.start_link(keys: :unique, name: registry_name)

    Logger.info("AggregateListenerSupervisor: Started for store #{store_id}")

    DynamicSupervisor.init(
      strategy: :one_for_one,
      # Don't restart listeners automatically - let the adapter handle it
      restart: :temporary
    )
  end

  # Helper functions to generate store-specific names
  defp supervisor_name(store_id), do: Module.concat(__MODULE__, store_id)
  defp registry_name(store_id), do: Module.concat([__MODULE__, store_id, Registry])

  @doc """
  Starts a new AggregateListener under supervision.

  Returns the PID of the started listener or an error.
  """
  @spec start_listener(map()) :: {:ok, pid()} | {:error, term()}
  def start_listener(config) do
    store_id = Map.fetch!(config, :store_id)
    stream_id = Map.fetch!(config, :stream_id)
    subscriber = Map.fetch!(config, :subscriber)

    supervisor_name = supervisor_name(store_id)
    registry_name = registry_name(store_id)

    # Create a unique key for this listener
    listener_key = {store_id, stream_id, subscriber}

    # Check if a listener already exists for this combination
    case Registry.lookup(registry_name, listener_key) do
      [{existing_pid, _}] when is_pid(existing_pid) ->
        # Check if the process is still alive
        if Process.alive?(existing_pid) do
          Logger.debug(
            "AggregateListenerSupervisor: Reusing existing listener for stream '#{stream_id}' (store: #{store_id})"
          )

          {:ok, existing_pid}
        else
          # Clean up dead process and start a new one
          Registry.unregister(registry_name, listener_key)
          do_start_listener(config, listener_key, supervisor_name, registry_name)
        end

      [] ->
        # No existing listener, start a new one
        do_start_listener(config, listener_key, supervisor_name, registry_name)
    end
  end

  @doc """
  Stops a specific AggregateListener.
  """
  @spec stop_listener(atom(), pid()) :: :ok
  def stop_listener(store_id, pid) when is_pid(pid) do
    supervisor_name = supervisor_name(store_id)

    case DynamicSupervisor.terminate_child(supervisor_name, pid) do
      :ok ->
        Logger.debug(
          "AggregateListenerSupervisor: Stopped listener #{inspect(pid)} (store: #{store_id})"
        )

        :ok

      {:error, :not_found} ->
        Logger.debug(
          "AggregateListenerSupervisor: Listener #{inspect(pid)} not found (store: #{store_id})"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "AggregateListenerSupervisor: Failed to stop listener #{inspect(pid)}: #{inspect(reason)} (store: #{store_id})"
        )

        :ok
    end
  end

  @doc """
  Stops all listeners for a specific store and stream combination.
  """
  @spec stop_listeners_for_stream(atom(), String.t()) :: :ok
  def stop_listeners_for_stream(store_id, stream_id) do
    registry_name = registry_name(store_id)

    # Find all listeners for this store/stream combination
    registry_name
    |> Registry.select([
      {{:"$1", :"$2", :"$3"},
       [
         {:andalso, {:==, {:element, 1, :"$1"}, store_id}, {:==, {:element, 2, :"$1"}, stream_id}}
       ], [:"$2"]}
    ])
    |> Enum.each(&stop_listener(store_id, &1))
  end

  @doc """
  Returns statistics about active listeners for a specific store.
  """
  @spec stats(atom()) :: %{
          total_listeners: non_neg_integer(),
          listeners_by_store: %{atom() => non_neg_integer()},
          active_streams: [String.t()]
        }
  def stats(store_id) do
    registry_name = registry_name(store_id)
    listeners = Registry.select(registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])

    listeners_by_store =
      listeners
      |> Enum.map(fn {store_id, _stream_id, _subscriber} -> store_id end)
      |> Enum.frequencies()

    active_streams =
      listeners
      |> Enum.map(fn {_store_id, stream_id, _subscriber} -> stream_id end)
      |> Enum.uniq()

    %{
      total_listeners: length(listeners),
      listeners_by_store: listeners_by_store,
      active_streams: active_streams
    }
  end

  @doc """
  Lists all active listeners with their details for a specific store.
  """
  @spec list_listeners(atom()) :: [
          %{store_id: atom(), stream_id: String.t(), subscriber: pid(), listener_pid: pid()}
        ]
  def list_listeners(store_id) do
    registry_name = registry_name(store_id)

    Registry.select(registry_name, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.map(fn {{store_id, stream_id, subscriber}, listener_pid} ->
      %{
        store_id: store_id,
        stream_id: stream_id,
        subscriber: subscriber,
        listener_pid: listener_pid
      }
    end)
  end

  # Private functions

  defp do_start_listener(config, listener_key, supervisor_name, registry_name) do
    child_spec = {AggregateListener, config}

    case DynamicSupervisor.start_child(supervisor_name, child_spec) do
      {:ok, pid} ->
        # Register the listener in our registry
        case Registry.register(registry_name, listener_key, nil) do
          {:ok, _} ->
            Logger.info(
              "AggregateListenerSupervisor: Started listener #{inspect(pid)} for stream '#{config.stream_id}' (store: #{config.store_id})"
            )

            {:ok, pid}

          {:error, {:already_registered, existing_pid}} ->
            # Race condition - another process started a listener
            DynamicSupervisor.terminate_child(supervisor_name, pid)
            {:ok, existing_pid}
        end

      {:error, reason} ->
        Logger.error(
          "AggregateListenerSupervisor: Failed to start listener for stream '#{config.stream_id}' (store: #{config.store_id}): #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
