defmodule ExESDB.Commanded.Adapter.SubscriptionProxy do
  @moduledoc """
  Simple GenServer that proxies ExESDB subscriptions to Commanded format.
  """

  use GenServer
  require Logger
  alias ExESDB.Commanded.Adapter.EventConverter
  alias ExESDBGater.API

  defstruct [
    :name,
    :subscriber,
    :stream,
    :store,
    :type,
    :selector,
    :start_version
  ]

  @doc """
  Starts a supervised subscription proxy process.
  """
  def start_link(metadata) do
    process_name = generate_process_name(metadata)
    GenServer.start_link(__MODULE__, metadata, name: process_name)
  end

  @doc """
  Legacy function for backward compatibility - now starts supervised process.
  """
  def start_proxy(metadata) do
    case start_link(metadata) do
      {:ok, pid} ->
        pid

      {:error, {:already_started, pid}} ->
        pid

      {:error, reason} ->
        Logger.error("Failed to start SubscriptionProxy: #{inspect(reason)}")
        throw({:subscription_proxy_start_failed, reason})
    end
  end

  # GenServer Callbacks

  @impl GenServer
  def init(metadata) do
    name = Map.get(metadata, :name, "proxy_#{:erlang.unique_integer()}")
    subscriber = Map.fetch!(metadata, :subscriber)
    store = Map.fetch!(metadata, :store)
    type = Map.fetch!(metadata, :type)
    selector = Map.fetch!(metadata, :selector)

    # Monitor the subscriber process
    Process.monitor(subscriber)

    state = %__MODULE__{
      name: name,
      subscriber: subscriber,
      stream: Map.get(metadata, :stream),
      store: store,
      type: type,
      selector: selector,
      start_version: Map.get(metadata, :start_version, 0)
    }

    case register_with_store(state) do
      :ok ->
        Logger.debug("SubscriptionProxy[#{name}]: Registered with store #{store}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("SubscriptionProxy[#{name}]: Failed to register: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info(:unsubscribe, state) do
    Logger.debug("SubscriptionProxy[#{state.name}]: Unsubscribing")
    {:stop, :normal, state}
  end

  def handle_info({:events, [%ExESDB.Schema.EventRecord{} = event_record]}, state) do
    handle_single_event(event_record, state)
    {:noreply, state}
  end

  def handle_info({:events, events}, state) when is_list(events) do
    handle_multiple_events(events, state)
    {:noreply, state}
  end

  def handle_info({:event_emitted, %ExESDB.Schema.EventRecord{} = event_record}, state) do
    # Treat event_emitted the same as regular events
    handle_single_event(event_record, state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Subscriber process died, clean up subscription
    if pid == state.subscriber do
      Logger.debug("SubscriptionProxy[#{state.name}]: Subscriber died, stopping")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(message, state) do
    handle_unknown_message(message, state)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.debug("SubscriptionProxy[#{state.name}]: Terminating")
    handle_unsubscribe(state)
    :ok
  end

  # Private helper functions

  defp generate_process_name(metadata) do
    store = Map.fetch!(metadata, :store)
    name = Map.get(metadata, :name, "proxy_#{:erlang.unique_integer()}")
    {:global, {store, name}}
  end

  defp register_with_store(state) do
    API.save_subscription(
      state.store,
      state.type,
      state.selector,
      state.name,
      state.start_version,
      self()
    )
  end

  defp handle_unsubscribe(state) do
    API.remove_subscription(state.store, state.type, state.selector, state.name)
  end

  defp handle_single_event(event_record, state) do
    Logger.debug("SubscriptionProxy[#{state.name}]: Received event #{event_record.event_type}")
    
    recorded_event = EventConverter.convert_event_record(event_record)
    send(state.subscriber, {:events, [recorded_event]})
  end

  defp handle_multiple_events(events, state) do
    Logger.debug("SubscriptionProxy[#{state.name}]: Received #{length(events)} events")
    
    converted_events = EventConverter.convert_events(events)
    send(state.subscriber, {:events, converted_events})
  end

  defp handle_unknown_message(message, state) do
    Logger.debug("SubscriptionProxy[#{state.name}]: Forwarding unknown message: #{inspect(message)}")
    send(state.subscriber, message)
  end

  # Child spec for supervision
  def child_spec(metadata) do
    name = Map.get(metadata, :name, "proxy_#{:erlang.unique_integer()}")

    %{
      id: {:subscription_proxy, name},
      start: {__MODULE__, :start_link, [metadata]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
