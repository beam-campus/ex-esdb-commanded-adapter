defmodule ExESDB.Commanded.Adapter do
  @moduledoc """
    An adapter for Commanded to use ExESDB as the event store.
    for reference, see: https://hexdocs.pm/commanded/Commanded.EventStore.Adapter.html
  """
  @behaviour Commanded.EventStore.Adapter

  require Logger

  alias ExESDBGater.API

  alias ExESDB.Commanded.Adapter.{StreamHelper, SubscriptionProxy, SubscriptionProxySupervisor}
  alias ExESDB.Commanded.AggregateListenerSupervisor

  alias ExESDB.Commanded.Mapper

  @type adapter_meta :: map()
  @type application :: Commanded.Application.t()
  @type config :: Keyword.t()
  @type stream_uuid :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any
  @type subscriber :: pid
  @type source_uuid :: String.t()
  @type error :: term

  # Delegate to StreamHelper for cleaner organization
  defp store_id(meta), do: StreamHelper.store_id(meta)
  defp stream_prefix(meta), do: StreamHelper.stream_prefix(meta)

  # Get PubSub name from ExESDB configuration
  defp pubsub_name do
    # First try to get from ex_esdb_gater configuration
    case Application.get_env(:ex_esdb_gater, :api, []) do
      config when is_list(config) ->
        Keyword.get(config, :pub_sub, :ex_esdb_pubsub)

      _ ->
        # Fallback to ex_esdb configuration
        case Application.get_env(:ex_esdb, :pub_sub) do
          # Default fallback
          nil -> :ex_esdb_pubsub
          pubsub -> pubsub
        end
    end
  end

  @spec ack_event(
          meta :: adapter_meta(),
          subscription :: any(),
          event :: Commanded.EventStore.RecordedEvent.t()
        ) :: :ok | {:error, error()}
  @impl Commanded.EventStore.Adapter
  def ack_event(_meta, subscription, _event) do
    # Handle different subscription formats
    case subscription do
      %{name: _subscription_name, subscriber: _subscriber_pid} ->
        # Legacy format - could ack to ExESDB if needed
        # For now, just return :ok since events are already processed
        :ok

      proxy_pid when is_pid(proxy_pid) ->
        # For proxy-based subscriptions, we don't need to ack to ExESDB
        # since the proxy handles the conversion and ExESDB doesn't require
        # explicit acknowledgment for the events we're consuming.
        # The acknowledgment in Commanded is just for flow control.
        :ok

      _ ->
        # Unknown format, but don't warn as this might be expected
        # in some configurations
        :ok
    end
  end

  @doc """
    Append one or more events to a stream atomically.
  """
  @spec append_to_stream(
          adapter_meta :: map(),
          stream_uuid :: String.t(),
          expected_version :: integer(),
          events :: list(Commanded.EventStore.EventData.t()),
          opts :: Keyword.t()
        ) ::
          :ok | {:error, :wrong_expected_version} | {:error, term()}
  @impl Commanded.EventStore.Adapter
  def append_to_stream(adapter_meta, stream_uuid, expected_version, events, _opts) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)
    full_stream_id = prefix <> stream_uuid

    # Normalize expected version for ExESDB 0-based indexing
    normalized_expected_version = StreamHelper.normalize_expected_version(expected_version)

    # Convert Commanded events to ExESDB format
    new_events = Enum.map(events, &Mapper.to_new_event/1)

    Logger.info("ADAPTER: Appending #{length(new_events)} events to stream #{full_stream_id}")

    Logger.info(
      "ADAPTER: Expected version: #{inspect(expected_version)} -> #{inspect(normalized_expected_version)}"
    )

    # Log event details for debugging
    Enum.each(new_events, fn event ->
      Logger.info("ADAPTER: Event type: #{event.event_type}, ID: #{event.event_id}")
    end)

    # Use normalized expected version
    case store
         |> API.append_events(full_stream_id, normalized_expected_version, new_events) do
      {:ok, new_version} ->
        Logger.info(
          "ADAPTER: Successfully appended events to #{full_stream_id}, new version: #{new_version}"
        )

        :ok

      {:error, reason} ->
        Logger.error("ADAPTER: Failed to append events to #{full_stream_id}: #{inspect(reason)}")
        StreamHelper.map_error(reason)
    end
  end

  @doc """
    Return a child spec defining all processes required by the event store.
  """
  @spec child_spec(
          application(),
          Keyword.t()
        ) ::
          {:ok, [:supervisor.child_spec() | {Module.t(), term} | Module.t()], adapter_meta}
  @impl Commanded.EventStore.Adapter
  def child_spec(application, opts) do
    store_id = Keyword.get(opts, :store_id, :ex_esdb)
    stream_prefix = Keyword.get(opts, :stream_prefix, "")
    serializer = Keyword.get(opts, :serializer, Jason)

    adapter_meta = %{
      store_id: store_id,
      stream_prefix: stream_prefix,
      serializer: serializer,
      application: application
    }

    # Start supervisors for managing subscriptions
    child_specs = [
      {AggregateListenerSupervisor, []},
      {SubscriptionProxySupervisor, []}
    ]

    {:ok, child_specs, adapter_meta}
  end

  @doc """
    Delete a snapshot of the current state of the event store.
  """
  @spec delete_snapshot(
          adapter_meta :: adapter_meta,
          source_uuid :: source_uuid
        ) :: :ok | {:error, error}
  @impl Commanded.EventStore.Adapter
  def delete_snapshot(adapter_meta, source_uuid) do
    store = store_id(adapter_meta)

    # Note: ExESDBGater.API.delete_snapshot expects (store, source_uuid, stream_uuid, version)
    # We'll use a default stream_uuid and version for now
    stream_uuid = "snapshots-" <> source_uuid
    version = 0

    case API.delete_snapshot(store, source_uuid, stream_uuid, version) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
    Delete a subscription.
  """
  @spec delete_subscription(
          adapter_meta :: adapter_meta,
          selector :: stream_uuid | String.t(),
          subscription_name :: subscription_name
        ) :: :ok | {:error, error}
  @impl Commanded.EventStore.Adapter
  def delete_subscription(adapter_meta, selector, subscription_name) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    {type, selector_value} = StreamHelper.stream_to_subscription_params(selector, prefix)

    case API.remove_subscription(store, type, selector_value, subscription_name) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Commanded.EventStore.Adapter
  def read_snapshot(adapter_meta, source_uuid) do
    store = store_id(adapter_meta)

    # Note: ExESDBGater.API.read_snapshot expects (store, source_uuid, stream_uuid, version)
    stream_uuid = "snapshots-" <> source_uuid
    version = 0

    case API.read_snapshot(store, source_uuid, stream_uuid, version) do
      {:ok, snapshot_record} ->
        {:ok, Mapper.to_snapshot_data(snapshot_record)}

      {:error, :not_found} ->
        {:error, :snapshot_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
    Record a snapshot of the current state of the event store.
  """
  @spec record_snapshot(
          adapter_meta :: adapter_meta,
          snapshot_data :: Commanded.EventStore.SnapshotData.t()
        ) :: :ok | {:error, error}
  @impl Commanded.EventStore.Adapter
  def record_snapshot(adapter_meta, snapshot_data) do
    store = store_id(adapter_meta)

    # Convert snapshot data to the format expected by ExESDBGater.API
    record = Mapper.to_snapshot_record(snapshot_data)

    # Note: ExESDBGater.API.record_snapshot expects (store, source_uuid, stream_uuid, version, snapshot_record)
    stream_uuid = "snapshots-" <> snapshot_data.source_uuid

    case API.record_snapshot(
           store,
           snapshot_data.source_uuid,
           stream_uuid,
           snapshot_data.source_version,
           record
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
    Streams events from the given stream, in the order in which they were
    originally written.
  """
  @spec stream_forward(
          adapter_meta :: adapter_meta,
          stream_uuid :: stream_uuid,
          start_version :: non_neg_integer,
          read_batch_size :: non_neg_integer
        ) ::
          Enumerable.t()
          | {:error, :stream_not_found}
          | {:error, error}
  @impl Commanded.EventStore.Adapter
  def stream_forward(adapter_meta, stream_uuid, start_version, read_batch_size) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)
    full_stream_id = prefix <> stream_uuid

    # Normalize start_version for ExESDB 0-based indexing
    # Commanded uses 1-based versioning, ExESDB uses 0-based
    normalized_start_version = case start_version do
      0 -> 0  # Keep 0 as 0 (start from beginning)
      version when version > 0 -> version - 1  # Convert 1-based to 0-based
      version -> version  # Negative versions (like -1 for latest) stay as-is
    end

    Logger.info(
      "ADAPTER: stream_forward for #{full_stream_id}, start_version: #{start_version} -> #{normalized_start_version}, batch_size: #{read_batch_size}"
    )

    case API.get_events(store, full_stream_id, normalized_start_version, read_batch_size, :forward) do
      {:ok, events} ->
        Logger.info(
          "ADAPTER: stream_forward found #{length(events)} events for #{full_stream_id}"
        )

        # Ensure we return an empty enumerable for no events, not nil
        case events do
          [] ->
            Logger.info("ADAPTER: stream_forward returning empty stream for #{full_stream_id}")
            []

          events when is_list(events) ->
            Logger.info(
              "ADAPTER: stream_forward converting #{length(events)} events for #{full_stream_id}"
            )
            
            # Log first and last event for debugging
            first_event = List.first(events)
            last_event = List.last(events)
            Logger.debug("ADAPTER: First event: #{inspect(first_event)}")
            Logger.debug("ADAPTER: Last event: #{inspect(last_event)}")

            converted_events = events |> Stream.map(&Mapper.to_recorded_event/1)
            
            # Log converted events
            converted_list = Enum.to_list(converted_events)
            if length(converted_list) > 0 do
              first_converted = List.first(converted_list)
              last_converted = List.last(converted_list)
              Logger.info("ADAPTER: Converted events stream_versions: #{first_converted.stream_version} to #{last_converted.stream_version}")
              
              # Debug first few events to check data integrity
              Enum.take(converted_list, 3)
              |> Enum.with_index()
              |> Enum.each(fn {event, index} ->
                Logger.debug("ADAPTER: Event #{index}: type=#{event.event_type}, data=#{inspect(event.data)}")
              end)
            end
            
            converted_list
        end

      {:error, :stream_not_found} ->
        Logger.info("ADAPTER: stream_forward - stream not found: #{full_stream_id}")
        {:error, :stream_not_found}

      {:error, reason} ->
        Logger.error("ADAPTER: stream_forward error for #{full_stream_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
    Create a transient subscription to a single event stream.

    The event store will publish any events appended to the given stream to the
    `subscriber` process as an `{:events, events}` message.

    The subscriber does not need to acknowledge receipt of the events.
  """
  @spec subscribe(
          adapter_meta :: adapter_meta,
          stream :: String.t()
        ) ::
          :ok | {:error, error}

  @impl Commanded.EventStore.Adapter
  def subscribe(adapter_meta, stream) do
    require Logger

    Logger.info(
      "ADAPTER: subscribe() called for stream: #{inspect(stream)} - using AggregateListener"
    )

    if StreamHelper.allowed_stream?(stream) do
      Logger.info("ADAPTER: Allowing subscription for #{inspect(stream)}")
      create_subscription(adapter_meta, stream)
    else
      Logger.info("ADAPTER: Creating AggregateListener for individual stream: #{inspect(stream)}")

      # For individual aggregate streams, use AggregateListener with PubSub
      create_aggregate_listener(adapter_meta, stream)
    end
  end

  # Helper function to create actual subscriptions for allowed cases
  defp create_subscription(adapter_meta, stream) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    {type, selector} = StreamHelper.stream_to_subscription_params(stream, prefix)

    # Create a transient subscription proxy to handle event conversion
    subscriber = self()

    proxy_pid =
      SubscriptionProxySupervisor.start_proxy(%{
        name: "transient_#{:erlang.unique_integer()}",
        subscriber: subscriber,
        stream: stream,
        store: store,
        type: type,
        selector: selector
      })

    # The SubscriptionProxy will register itself with the store during initialization
    :ok
  end

  # Helper function to create AggregateListener for individual aggregate streams
  defp create_aggregate_listener(adapter_meta, stream) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)
    target_stream_id = prefix <> stream  # This is the stream to filter for
    subscriber = self()

    # Create a listener config
    listener_config = %{
      store_id: store,
      stream_id: target_stream_id,  # Filter for this specific stream
      subscriber: subscriber,
      pubsub_name: pubsub_name(),
      # Disable historical replay for transient subscriptions to prevent duplicates
      # Commanded handles aggregate loading via stream_forward separately
      replay_historical_events?: false
    }

    case AggregateListenerSupervisor.start_listener(listener_config) do
      {:ok, _listener_pid} ->
        Logger.info("ADAPTER: Started AggregateListener for stream '#{target_stream_id}' on topic '#{store}:$all'")
        :ok

      {:error, reason} ->
        Logger.error(
          "ADAPTER: Failed to start AggregateListener for stream '#{target_stream_id}': #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
    Create a persistent subscription to an event stream.
  """
  @spec subscribe_to(
          adapter_meta :: adapter_meta,
          stream :: String.t(),
          subscription_name :: String.t(),
          subscriber :: pid,
          start_from :: :origin | :current | non_neg_integer,
          opts :: Keyword.t()
        ) ::
          {:ok, subscription}
          | {:error, :subscription_already_exists}
          | {:error, error}

  @impl Commanded.EventStore.Adapter
  def subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from, _opts) do
    require Logger

    Logger.warning(
      "ADAPTER: subscribe_to() called for stream: #{inspect(stream)}, subscription: #{subscription_name}"
    )

    if StreamHelper.allowed_stream?(stream) do
      Logger.info(
        "ADAPTER: Allowing persistent subscription: #{subscription_name} for #{inspect(stream)}"
      )

      do_subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from)
    else
      Logger.warning(
        "ADAPTER: BLOCKING individual stream subscription: #{subscription_name} for #{inspect(stream)} - Use event-type projections instead"
      )

      # Don't create subscriptions for individual aggregate streams
      # Let the event-type projection system handle events instead
      {:error, :subscription_blocked}
    end
  end

  # Helper function to actually create subscriptions for allowed cases
  defp do_subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    {type, selector} = StreamHelper.stream_to_subscription_params(stream, prefix)
    start_version = StreamHelper.normalize_start_version(start_from)

    # Start a supervised subscription proxy process
    proxy_pid =
      SubscriptionProxySupervisor.start_proxy(%{
        name: subscription_name,
        subscriber: subscriber,
        stream: stream,
        store: store,
        type: type,
        selector: selector,
        start_version: start_version
      })

    # The SubscriptionProxy will register itself with the store during initialization
    {:ok, proxy_pid}
  end

  @impl Commanded.EventStore.Adapter
  def unsubscribe(_adapter_meta, subscription_pid) when is_pid(subscription_pid) do
    # Send a message to the proxy process to trigger cleanup
    send(subscription_pid, :unsubscribe)
    :ok
  end

  def unsubscribe(adapter_meta, subscription) do
    case subscription do
      %{name: subscription_name, stream: stream} ->
        # Legacy subscription format - handle directly
        store = store_id(adapter_meta)
        prefix = stream_prefix(adapter_meta)

        {type, selector} = StreamHelper.stream_to_subscription_params(stream, prefix)

        case API.remove_subscription(store, type, selector, subscription_name) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        Logger.warning(
          "Unable to unsubscribe - invalid subscription format: #{inspect(subscription)}"
        )

        :ok
    end
  end
end
