defmodule ExESDB.Commanded.Adapter do
  @moduledoc """
    An adapter for Commanded to use ExESDB as the event store.
    for reference, see: https://hexdocs.pm/commanded/Commanded.EventStore.Adapter.html
  """
  @behaviour Commanded.EventStore.Adapter

  require Logger

  alias ExESDBGater.API
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

  defp store_id(meta), do: Map.get(meta, :store_id, :ex_esdb)
  defp stream_prefix(meta), do: Map.get(meta, :stream_prefix, "")

  @spec ack_event(
          meta :: adapter_meta(),
          subscription :: any(),
          event :: Commanded.EventStore.RecordedEvent.t()
        ) :: :ok | {:error, error()}
  @impl Commanded.EventStore.Adapter
  def ack_event(meta, subscription, event) do
    store = store_id(meta)

    # Note: ExESDBGater.API.ack_event expects (store, subscription_name, subscriber_pid, event)
    # We'll extract these from the subscription data structure
    case subscription do
      %{name: subscription_name, subscriber: subscriber_pid} ->
        store
        |> API.ack_event(subscription_name, subscriber_pid, event)

        :ok

      _ ->
        Logger.warning(
          "Unable to ack event - invalid subscription format: #{inspect(subscription)}"
        )

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

    # Convert Commanded events to ExESDB format
    new_events = Enum.map(events, &Mapper.to_new_event/1)

    # Note: ExESDBGater.API.append_events expects (store, stream_id, events)
    # We'll need to handle expected_version separately since the API doesn't seem to support it directly
    case store
         |> API.append_events(full_stream_id, expected_version, new_events) do
      {:ok, _new_version} -> :ok
      {:error, reason} -> {:error, reason}
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

    # ExESDB Gater is expected to be running as a separate system
    # So we don't need to start additional children here
    child_specs = []

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
          selector :: stream_uuid | :all,
          subscription_name :: subscription_name
        ) :: :ok | {:error, error}
  @impl Commanded.EventStore.Adapter
  def delete_subscription(adapter_meta, selector, subscription_name) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    # Determine subscription type and selector based on stream
    {type, selector_value} =
      case selector do
        :all -> {:by_stream, "$all"}
        stream_uuid when is_binary(stream_uuid) -> {:by_stream, "$#{prefix}#{stream_uuid}"}
      end

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

    case API.get_events(store, full_stream_id, start_version, read_batch_size, :forward) do
      {:ok, events} ->
        events
        |> Stream.map(&Mapper.to_recorded_event/1)

      {:error, :stream_not_found} ->
        {:error, :stream_not_found}

      {:error, reason} ->
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
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    # Determine subscription type and selector based on stream
    {type, selector} =
      case stream do
        "$all" -> {:by_stream, "$all"}
        stream_id when is_binary(stream_id) -> {:by_stream, "$#{prefix}#{stream_id}"}
      end

    # Create a transient subscription (subscription_name = "transient")
    case API.save_subscription(store, type, selector, "transient", 0, self()) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
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
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    # Determine subscription type and selector based on stream
    {type, selector} =
      case stream do
        "$all" -> {:by_stream, "$all"}
        stream_id when is_binary(stream_id) -> {:by_stream, "$#{prefix}#{stream_id}"}
      end

    # Convert start_from to version number
    start_version =
      case start_from do
        :origin -> 0
        # Start from latest
        :current -> -1
        version when is_integer(version) -> version
      end

    # Save the subscription
    case API.save_subscription(
           store,
           type,
           selector,
           subscription_name,
           start_version,
           subscriber
         ) do
      :ok ->
        # Return a subscription handle that includes the info needed for ack_event
        subscription = %{
          name: subscription_name,
          subscriber: subscriber,
          stream: stream,
          store: store
        }

        {:ok, subscription}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Commanded.EventStore.Adapter
  def unsubscribe(adapter_meta, subscription) do
    store = store_id(adapter_meta)

    # Extract subscription info from the subscription handle
    case subscription do
      %{name: subscription_name, stream: stream} ->
        # Determine subscription type and selector based on stream
        prefix = stream_prefix(adapter_meta)

        {type, selector} =
          case stream do
            "$all" -> {:by_stream, "$all"}
            stream_id when is_binary(stream_id) -> {:by_stream, "$#{prefix}#{stream_id}"}
          end

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
