defmodule ExESDB.Commanded.Adapter.SubscriptionProxy do
  @moduledoc """
  Supervised GenServer that handles subscription proxies for converting ExESDB events to Commanded format.

  This process is supervised and maintains its registration with the ExESDB store,
  ensuring event delivery continues even after process restarts.

  There is an aggressive re-registration process that runs periodically 
  to ensure the subscription PID is current. This is mainly to deal with 
  new leader election scenarios where the emitter processes are restarted.

  We should think of a mechanism to handle this better in the future.



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
    :target_stream_id,
    :start_version,
    :subscription_registered
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

    # Monitor the subscriber process for transient subscriptions
    if String.starts_with?(name, "transient_") do
      Process.monitor(subscriber)
    end

    state = %__MODULE__{
      name: name,
      subscriber: subscriber,
      stream: Map.get(metadata, :stream),
      store: store,
      type: type,
      selector: selector,
      target_stream_id: Map.get(metadata, :target_stream_id),
      start_version: Map.get(metadata, :start_version, 0),
      subscription_registered: false
    }

    # Register with ExESDB store
    case register_with_store(state) do
      :ok ->
        Logger.info(
          "SubscriptionProxy[#{name}] (store: #{store}): Started and registered with store"
        )

        # Schedule initial aggressive re-registration to ensure immediate propagation
        schedule_reregistration(:initial)

        {:ok, %{state | subscription_registered: true}}

      {:error, reason} ->
        Logger.error(
          "SubscriptionProxy[#{name}] (store: #{store}): Failed to register with store: #{inspect(reason)}"
        )

        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:set_subscription_metadata, new_metadata}, state) do
    # Update state with new metadata
    updated_state = Map.merge(state, Map.take(new_metadata, [:target_stream_id]))
    {:noreply, updated_state}
  end

  def handle_info(:unsubscribe, state) do
    Logger.info(
      "SubscriptionProxy[#{state.name}] (store: #{state.store}): Received unsubscribe message"
    )

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
      Logger.info(
        "SubscriptionProxy[#{state.name}] (store: #{state.store}): Subscriber #{inspect(pid)} died, stopping proxy"
      )

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:reregister_pid, state) do
    Logger.debug(
      "SubscriptionProxy[#{state.name}] (store: #{state.store}): Periodic PID re-registration"
    )

    # Re-register with store to ensure PID is current
    case register_with_store(state) do
      :ok ->
        # Schedule next re-registration (normal interval)
        schedule_reregistration(:normal)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "SubscriptionProxy[#{state.name}] (store: #{state.store}): Failed to re-register PID: #{inspect(reason)}"
        )

        # Still schedule next attempt (retry faster)
        schedule_reregistration(:retry)
        {:noreply, state}
    end
  end

  def handle_info(message, state) do
    handle_unknown_message(message, state)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info(
      "SubscriptionProxy[#{state.name}] (store: #{state.store}): Terminating: #{inspect(reason)}"
    )

    if state.subscription_registered do
      handle_unsubscribe(state)
    end

    :ok
  end

  # Private helper functions

  # Generate a store-aware process name to avoid conflicts in umbrella applications
  defp generate_process_name(metadata) do
    store = Map.fetch!(metadata, :store)
    name = Map.get(metadata, :name, "proxy_#{:erlang.unique_integer()}")

    # Use global naming with store prefix to avoid conflicts
    {:global, {store, name}}
  end

  # Schedule periodic PID re-registration with different intervals
  defp schedule_reregistration(mode) do
    interval =
      case mode do
        # Fast initial re-registration
        :initial -> :timer.seconds(5)
        # Faster retry on failure
        :retry -> :timer.seconds(10)
        # Normal periodic interval
        :normal -> :timer.seconds(30)
      end

    Process.send_after(self(), :reregister_pid, interval)
  end

  defp register_with_store(state) do
    # Update the subscription with our new PID using save_subscription
    # This will either create a new subscription or update the existing one with our PID
    API.save_subscription(
      state.store,
      state.type,
      state.selector,
      state.name,
      state.start_version,
      self()
    )
  end

  # Handle subscription cleanup
  defp handle_unsubscribe(state) do
    API.remove_subscription(state.store, state.type, state.selector, state.name)
    # Process exits naturally
  end

  # Handle single event conversion and forwarding
  defp handle_single_event(event_record, state) do
    Logger.info(
      "ADAPTER PROXY [#{state.selector}]: Received EventRecord #{event_record.event_type} for stream #{event_record.event_stream_id}"
    )

    # Check if we need to filter events for a specific stream
    should_forward =
      case state.target_stream_id do
        # No filtering, forward all events
        nil -> true
        target_stream_id -> event_record.event_stream_id == target_stream_id
      end

    if should_forward do
      Logger.debug(
        "Adapter proxy converting EventRecord to RecordedEvent for subscriber #{inspect(state.subscriber)}"
      )

      recorded_event = EventConverter.convert_event_record(event_record)

      Logger.info(
        "ADAPTER PROXY [#{state.selector}]: Sending converted event #{recorded_event.event_type} to subscriber #{inspect(state.subscriber)}"
      )

      Logger.debug(
        "ADAPTER PROXY [#{state.selector}]: About to send event to #{inspect(state.subscriber)}"
      )

      send(state.subscriber, {:events, [recorded_event]})
      Logger.info("ADAPTER PROXY [#{state.selector}]: Event sent successfully")
    else
      Logger.debug(
        "ADAPTER PROXY [#{state.selector}]: Filtering out event for stream #{event_record.event_stream_id} (target: #{state.target_stream_id})"
      )
    end
  end

  # Handle multiple events
  defp handle_multiple_events(events, state) do
    Logger.info("ADAPTER PROXY [#{state.selector}]: Received #{length(events)} events")
    # Filter events if target_stream_id is specified
    filtered_events =
      case state.target_stream_id do
        # No filtering
        nil ->
          events

        target_stream_id ->
          Enum.filter(events, fn
            %ExESDB.Schema.EventRecord{event_stream_id: ^target_stream_id} -> true
            _ -> false
          end)
      end

    if length(filtered_events) > 0 do
      Logger.info(
        "ADAPTER PROXY [#{state.selector}]: Forwarding #{length(filtered_events)} filtered events to subscriber #{inspect(state.subscriber)}"
      )

      converted_events = EventConverter.convert_events(filtered_events)
      send(state.subscriber, {:events, converted_events})
      Logger.info("ADAPTER PROXY [#{state.selector}]: Multiple events sent successfully")
    else
      Logger.debug("ADAPTER PROXY [#{state.selector}]: All #{length(events)} events filtered out")
    end
  end

  # Handle unknown messages
  defp handle_unknown_message(message, state) do
    Logger.info(
      "ADAPTER PROXY [#{state.selector}]: Received unknown message: #{inspect(message)}"
    )

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
