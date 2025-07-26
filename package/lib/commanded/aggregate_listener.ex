defmodule ExESDB.Commanded.AggregateListener do
  @moduledoc """
  A process that subscribes to the EventStore's Phoenix PubSub `<store>:$all` topic
  and filters events by stream_id for aggregate transient subscriptions.

  Simplified with Swarm for process distribution.

  Each AggregateListener processes:
  1. Subscribes to the `<store>:$all` Phoenix PubSub topic
  2. Filters incoming events based on the target stream_id
  3. Transforms ExESDB.Schema.EventRecord to Commanded.EventStore.RecordedEvent
  4. Forwards matching events to the subscriber process
  """

  use GenServer
  require Logger
  alias ExESDB.Commanded.Mapper
  alias ExESDBGater.API
  alias Phoenix.PubSub

  @retry_interval 1_000  # Retry interval for Swarm registration

  @type listener_config :: %{
          store_id: atom(),
          stream_id: String.t(),
          subscriber: pid(),
          replay_historical_events?: boolean()
        }

  # Public API

  @doc """
  Starts an AggregateListener for the given stream using Swarm.

  ## Parameters
  - config: Map containing:
    - store_id: The EventStore identifier
    - stream_id: The target stream to filter events for
    - subscriber: The process to send filtered events to
    - replay_historical_events?: Whether to replay historical events on startup (defaults to true)
  """
  @spec start_link(listener_config()) :: {:ok, pid()} | {:error, term()}
  def start_link(config) do
    store_id = Map.fetch!(config, :store_id)
    key = :erlang.phash2({store_id, node()})
    name = {:aggregate_listener, key}

    case Swarm.register_name(name, __MODULE__, :start_link, [config]) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_registered, pid}} ->
        {:ok, pid}

      {:error, _reason} ->
        # Start the process anyway and retry registration
        {:ok, pid} = GenServer.start_link(__MODULE__, config)
        Process.send_after(pid, {:retry_registration, name, config}, @retry_interval)
        {:ok, pid}
    end
  end

  @doc """
  Starts an AggregateListener without linking to the calling process.
  Useful for transient subscriptions where we don't want to crash the caller.
  """
  @spec start(listener_config()) :: {:ok, pid()} | {:error, term()}
  def start(config) do
    GenServer.start(
      __MODULE__,
      config,
      name: Module.concat(__MODULE__, hash_key(config.store_id))
    )
  end

  @doc """
  Stops the AggregateListener process.
  """
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # GenServer implementation

  @impl GenServer
  def init(config) do
    store_id = Map.fetch!(config, :store_id)
    stream_id = Map.fetch!(config, :stream_id)
    subscriber = Map.fetch!(config, :subscriber)
    replay_historical = Map.get(config, :replay_historical_events?, true)
    Swarm.register_name(swarm_key(store_id), self())

    # Subscribe to the store's $all topic on Phoenix PubSub
    topic = "#{store_id}:$all"

    Logger.info("AggregateListener: Subscribing to :ex_esdb_events PubSub on topic '#{topic}'")
    :ok = PubSub.subscribe(:ex_esdb_events, topic)

    state = %{
      store_id: store_id,
      stream_id: stream_id,
      subscriber: subscriber,
      topic: topic,
      events_forwarded: 0,
      events_filtered: 0,
      replay_historical: replay_historical,
      historical_replay_done: false
    }

    Logger.info(
      "AggregateListener[#{Map.get(config, :store_id, :unknown)}]: Started for stream '#{stream_id}' on topic '#{topic}'"
    )

    # If we should replay historical events, do it after initialization
    state =
      if replay_historical do
        send(self(), :replay_historical_events)
        state
      else
        # Mark as done if we're not replaying
        %{state | historical_replay_done: true}
      end

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:events, events}, state) when is_list(events) do
    Logger.info("AggregateListener[#{state.store_id}]: Received #{length(events)} events on topic '#{state.topic}'")
    # Filter events for our target stream and forward them
    filtered_events = filter_and_transform_events(events, state.stream_id)

    if length(filtered_events) > 0 do
      # Send the filtered events to the subscriber
      send(state.subscriber, {:events, filtered_events})

      Logger.debug(
        "AggregateListener[#{state.store_id}]: Forwarded #{length(filtered_events)} events for stream '#{state.stream_id}'"
      )
    end

    # Update statistics
    new_state = %{
      state
      | events_forwarded: state.events_forwarded + length(filtered_events),
        events_filtered: state.events_filtered + length(events) - length(filtered_events)
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:event, event}, state) do
    # Handle single event (some PubSub implementations might send individual events)
    handle_info({:events, [event]}, state)
  end

  @impl GenServer
  def handle_info(:replay_historical_events, state) do
    Logger.info(
      "AggregateListener[#{state.store_id}]: Replaying historical events for stream '#{state.stream_id}'"
    )

    case replay_historical_events(state) do
      :ok ->
        Logger.info(
          "AggregateListener[#{state.store_id}]: Historical replay completed for stream '#{state.stream_id}'"
        )

        new_state = %{state | historical_replay_done: true}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error(
          "AggregateListener[#{state.store_id}]: Failed to replay historical events for stream '#{state.stream_id}': #{inspect(reason)}"
        )

        # Continue anyway, but mark as done to avoid blocking real-time events
        new_state = %{state | historical_replay_done: true}
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(:unsubscribe, state) do
    Logger.info("AggregateListener[#{state.store_id}]: Unsubscribing from '#{state.topic}'")
    :ok = PubSub.unsubscribe(:ex_esdb_events, state.topic)
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{subscriber: pid} = state) do
    Logger.info(
      "AggregateListener[#{state.store_id}]: Subscriber process #{inspect(pid)} died (#{inspect(reason)}), stopping listener"
    )

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:retry_registration, name, config}, state) do
    case Swarm.register_name(name, __MODULE__, :start_link, [config]) do
      {:ok, _pid} ->
        {:noreply, state}

      {:error, {:already_registered, _pid}} ->
        {:noreply, state}

      {:error, _reason} ->
        Process.send_after(self(), {:retry_registration, name, config}, @retry_interval)
        {:noreply, state}
    end
  end

  def handle_info({:swarm, :die}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:swarm, :begin_handoff}, state) do
    {:noreply, state}
  end

  def handle_info({:swarm, :end_handoff}, state) do
    {:noreply, state}
  end

  def handle_info({:swarm, :resolve_conflict}, state) do
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug(
      "AggregateListener[#{state.store_id}]: Received unexpected message: #{inspect(msg)}"
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      stream_id: state.stream_id,
      topic: state.topic,
      events_forwarded: state.events_forwarded,
      events_filtered: state.events_filtered,
      subscriber: state.subscriber
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info(
      "AggregateListener[#{state.store_id}]: Terminating for stream '#{state.stream_id}' (reason: #{inspect(reason)})"
    )

    :ok = unsubscribe(state.topic)

    :ok
  end

  defp unsubscribe(topic) do
    # Unsubscribe from PubSub if still subscribed
    try do
      :ok = PubSub.unsubscribe(:ex_esdb_events, topic)
    catch
      _, _ -> :ok
    end
  end

  defp hash_key(store_id), do: Integer.to_string(:erlang.phash2({store_id, node()}))
  def swarm_key(store_id), do: {:aggregate_listener, hash_key(store_id)}

  # Private functions
  @spec filter_and_transform_events(
          events :: [ExESDB.Schema.EventRecord.t()],
          target_stream_id :: String.t()
        ) :: [Commanded.EventStore.RecordedEvent.t()]
  defp filter_and_transform_events(events, target_stream_id) when is_list(events) do
    events
    |> Enum.filter(fn event ->
      # Filter events that belong to our target stream
      case event do
        %{stream_id: ^target_stream_id} -> true
        %ExESDB.Schema.EventRecord{event_stream_id: ^target_stream_id} -> true
        _ -> false
      end
    end)
    |> Enum.map(&transform_event/1)
  end

  @spec transform_event(ExESDB.Schema.EventRecord.t()) :: Commanded.EventStore.RecordedEvent.t()
  defp transform_event(event_record) do
    try do
      Mapper.to_recorded_event(event_record)
    rescue
      error ->
        Logger.error(
          "AggregateListener: Failed to transform event: #{inspect(error)}, event: #{inspect(event_record)}"
        )

        # Return a basic error event that won't break the stream
        %Commanded.EventStore.RecordedEvent{
          event_id: UUID.uuid4(),
          event_number: 0,
          stream_id: event_record.stream_id || "unknown",
          stream_version: 0,
          event_type: "TransformationError",
          data: %{error: inspect(error), original_event: inspect(event_record)},
          metadata: %{transformation_error: true},
          created_at: DateTime.utc_now()
        }
    end
  end

  # Replay historical events from the stream
  @spec replay_historical_events(map()) :: :ok | {:error, term()}
  defp replay_historical_events(state) do
    store_id = state.store_id
    stream_id = state.stream_id
    subscriber = state.subscriber

    Logger.debug("AggregateListener: Starting historical replay for stream '#{stream_id}'")

    try do
      last_version =
        store_id
        |> API.get_version(stream_id)

      # Validate last_version is a proper integer before proceeding
      case last_version do
        version when is_integer(version) and version >= 0 ->
          # Read all events from the beginning of the stream
          case API.get_events(store_id, stream_id, 0, version, :forward) do
            {:ok, []} ->
              Logger.debug(
                "AggregateListener: No historical events found for stream '#{stream_id}'"
              )

              :ok

            {:ok, events} when is_list(events) ->
              Logger.debug(
                "AggregateListener: Found #{length(events)} historical events for stream '#{stream_id}'"
              )

              # Transform and send historical events
              transformed_events =
                events
                |> Enum.map(&transform_event/1)

              # Send events to subscriber in the same format as real-time events
              send(subscriber, {:events, transformed_events})

              Logger.debug(
                "AggregateListener: Sent #{length(transformed_events)} historical events for stream '#{stream_id}'"
              )

              :ok

            {:error, :stream_not_found} ->
              Logger.debug(
                "AggregateListener: Stream '#{stream_id}' not found, no historical events to replay"
              )

              :ok

            {:error, reason} ->
              Logger.warning(
                "AggregateListener: Failed to read historical events for stream '#{stream_id}': #{inspect(reason)}"
              )

              {:error, reason}
          end

        -1 ->
          # Stream exists but has no events (version -1)
          Logger.debug(
            "AggregateListener: Stream '#{stream_id}' has no events, skipping historical replay"
          )

          :ok

        invalid_version ->
          # Handle invalid version (nil, atom, string, etc.)
          Logger.warning(
            "AggregateListener: Invalid version #{inspect(invalid_version)} for stream '#{stream_id}', skipping historical replay"
          )

          :ok
      end
    rescue
      error ->
        Logger.error(
          "AggregateListener: Exception during historical replay for stream '#{stream_id}': #{inspect(error)}"
        )

        {:error, error}
    end
  end
end
