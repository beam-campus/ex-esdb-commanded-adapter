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
  
  # Version normalization functions for ExESDB 0-based indexing
  @doc """
  Normalizes Commanded expected versions to ExESDB expected versions.
  
  Commanded uses:
  - :no_stream for new streams (expecting stream doesn't exist)
  - :any_version for any version (no version checking)
  - :stream_exists for existing streams (expecting stream exists but don't care about version)
  - integer >= 0 for specific version expectations
  
  ExESDB uses:
  - -1 for new streams (stream doesn't exist yet)
  - :any for any version (no version checking)  
  - integer >= -1 for specific version expectations
  """
  defp normalize_expected_version(:no_stream), do: -1
  defp normalize_expected_version(:any_version), do: :any
  defp normalize_expected_version(:stream_exists), do: :stream_exists
  # Commanded expected version is the version they want to write
  # ExESDB expected version is the current version of the stream
  # So: Commanded expected N means ExESDB current should be N-1
  defp normalize_expected_version(version) when is_integer(version) and version >= 0, do: version - 1
  
  @doc """
  Maps ExESDB error responses to Commanded error format.
  """
  defp map_error({:wrong_expected_version, actual_version}) do
    Logger.error("ADAPTER: Wrong expected version, actual version is: #{actual_version}")
    {:error, :wrong_expected_version}
  end
  defp map_error({:error, {:wrong_expected_version, actual_version}}), do: map_error({:wrong_expected_version, actual_version})
  defp map_error(:stream_not_found), do: {:error, :stream_not_found}
  defp map_error(error), do: {:error, error}

  @spec ack_event(
          meta :: adapter_meta(),
          subscription :: any(),
          event :: Commanded.EventStore.RecordedEvent.t()
        ) :: :ok | {:error, error()}
  @impl Commanded.EventStore.Adapter
  def ack_event(_meta, subscription, _event) do
    # Handle different subscription formats
    case subscription do
      %{name: subscription_name, subscriber: subscriber_pid} ->
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
    normalized_expected_version = normalize_expected_version(expected_version)

    # Convert Commanded events to ExESDB format
    new_events = Enum.map(events, &Mapper.to_new_event/1)
    
    Logger.info("ADAPTER: Appending #{length(new_events)} events to stream #{full_stream_id}")
    Logger.info("ADAPTER: Expected version: #{inspect(expected_version)} -> #{inspect(normalized_expected_version)}")
    
    # Log event details for debugging
    Enum.each(new_events, fn event ->
      Logger.info("ADAPTER: Event type: #{event.event_type}, ID: #{event.event_id}")
    end)

    # Use normalized expected version
    case store
         |> API.append_events(full_stream_id, normalized_expected_version, new_events) do
      {:ok, new_version} -> 
        Logger.info("ADAPTER: Successfully appended events to #{full_stream_id}, new version: #{new_version}")
        :ok
      {:error, reason} -> 
        Logger.error("ADAPTER: Failed to append events to #{full_stream_id}: #{inspect(reason)}")
        map_error(reason)
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
          selector :: stream_uuid | String.t(),
          subscription_name :: subscription_name
        ) :: :ok | {:error, error}
  @impl Commanded.EventStore.Adapter
  def delete_subscription(adapter_meta, selector, subscription_name) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    # Determine subscription type and selector based on stream
    {type, selector_value} =
      case selector do
        "$all" -> {:by_stream, "$all"}
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
    
    Logger.info("ADAPTER: stream_forward for #{full_stream_id}, start_version: #{start_version}, batch_size: #{read_batch_size}")

    case API.get_events(store, full_stream_id, start_version, read_batch_size, :forward) do
      {:ok, events} ->
        Logger.info("ADAPTER: stream_forward found #{length(events)} events for #{full_stream_id}")
        
        # Ensure we return an empty enumerable for no events, not nil
        case events do
          [] ->
            Logger.info("ADAPTER: stream_forward returning empty stream for #{full_stream_id}")
            []
          events when is_list(events) ->
            Logger.info("ADAPTER: stream_forward converting #{length(events)} events for #{full_stream_id}")
            events
            |> Stream.map(&Mapper.to_recorded_event/1)
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
    
    # Log the subscription attempt to understand what's calling this
    Logger.warning("ADAPTER: subscribe() called for stream: #{inspect(stream)} - PREVENTING automatic stream subscription")
    
    # Prevent automatic stream subscriptions to avoid unwanted emitter pools
    # Only allow $all and event type subscriptions
    case stream do
      :all -> 
        Logger.info("ADAPTER: Allowing $all subscription")
        create_subscription(adapter_meta, stream)
      "$all" -> 
        Logger.info("ADAPTER: Allowing $all subscription")
        create_subscription(adapter_meta, stream)
      "$et-" <> _event_type -> 
        Logger.info("ADAPTER: Allowing event type subscription for #{stream}")
        create_subscription(adapter_meta, stream)
      stream_id when is_binary(stream_id) -> 
        Logger.warning("ADAPTER: BLOCKING stream subscription for #{stream_id} - use event-type subscriptions instead")
        # Return :ok but don't create the subscription
        # This prevents emitter pools from being created for individual streams
        :ok
      _ -> 
        Logger.warning("ADAPTER: BLOCKING unknown subscription type: #{inspect(stream)}")
        :ok
    end
  end
  
  # Helper function to create actual subscriptions for allowed cases
  defp create_subscription(adapter_meta, stream) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    # Determine subscription type and selector based on stream
    {type, selector} =
      case stream do
        :all -> {:by_stream, "$all"}
        "$all" -> {:by_stream, "$all"}
        "$et-" <> event_type -> {:by_event_type, event_type}  # EventStore event type stream
        stream_id when is_binary(stream_id) -> {:by_stream, "$#{prefix}#{stream_id}"}
      end

    # Create a transient subscription proxy to handle event conversion
    subscriber = self()
    proxy_pid = spawn(fn ->
      subscription_loop(%{
        name: "transient_#{:erlang.unique_integer()}",
        subscriber: subscriber,
        stream: stream,
        store: store,
        type: type,
        selector: selector
      })
    end)
    
    # Create a transient subscription with the proxy as the subscriber
    case API.save_subscription(store, type, selector, "transient", 0, proxy_pid) do
      :ok -> :ok
      {:error, reason} -> 
        # Clean up the proxy process if subscription failed
        Process.exit(proxy_pid, :kill)
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
    
    # Log the subscription attempt
    Logger.warning("ADAPTER: subscribe_to() called for stream: #{inspect(stream)}, subscription: #{subscription_name}")
    
    # Block individual stream subscriptions, only allow $all and event type subscriptions
    case stream do
      :all -> 
        Logger.info("ADAPTER: Allowing persistent $all subscription: #{subscription_name}")
        do_subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from)
      "$all" -> 
        Logger.info("ADAPTER: Allowing persistent $all subscription: #{subscription_name}")
        do_subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from)
      "$et-" <> _event_type -> 
        Logger.info("ADAPTER: Allowing persistent event type subscription: #{subscription_name} for #{stream}")
        do_subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from)
      stream_id when is_binary(stream_id) -> 
        Logger.warning("ADAPTER: BLOCKING persistent stream subscription: #{subscription_name} for #{stream_id}")
        # Return a fake subscription to prevent errors in Commanded
        {:ok, self()}
      _ -> 
        Logger.warning("ADAPTER: BLOCKING unknown persistent subscription type: #{inspect(stream)}")
        {:ok, self()}
    end
  end
  
  # Helper function to actually create subscriptions for allowed cases
  defp do_subscribe_to(adapter_meta, stream, subscription_name, subscriber, start_from) do
    store = store_id(adapter_meta)
    prefix = stream_prefix(adapter_meta)

    # Determine subscription type and selector based on stream
    {type, selector} =
      case stream do
        :all -> {:by_stream, "$all"}
        "$all" -> {:by_stream, "$all"}
        "$et-" <> event_type -> {:by_event_type, event_type}  # EventStore event type stream
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

    # Start a subscription proxy process that stores metadata for cleanup
    # and forwards ExESDB events to Commanded in the correct format
    proxy_pid = spawn(fn ->
      subscription_loop(%{
        name: subscription_name,
        subscriber: subscriber,
        stream: stream,
        store: store,
        type: type,
        selector: selector
      })
    end)
    
    # Save the subscription with the proxy process as the subscriber
    case API.save_subscription(
           store,
           type,
           selector,
           subscription_name,
           start_version,
           proxy_pid
         ) do
      :ok ->
        # Store subscription metadata in the proxy process state for ack_event
        # But return the proxy PID for Commanded to monitor
        send(proxy_pid, {:set_subscription_metadata, %{
          name: subscription_name,
          subscriber: subscriber,
          stream: stream,
          type: type,
          selector: selector
        }})
        {:ok, proxy_pid}

        {:error, reason} ->
        # Clean up the proxy process if subscription failed
        Process.exit(proxy_pid, :kill)
        {:error, reason}
    end
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

        {type, selector} =
          case stream do
            :all -> {:by_stream, "$all"}
            "$all" -> {:by_stream, "$all"}
            "$et-" <> event_type -> {:by_event_type, event_type}
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

  # Helper function to parse metadata (handles both binary and map formats)
  defp parse_metadata(nil), do: %{}
  defp parse_metadata(metadata) when is_map(metadata), do: metadata
  defp parse_metadata(metadata) when is_binary(metadata) do
    try do
      case Jason.decode(metadata) do
        {:ok, parsed} when is_map(parsed) -> 
          # Convert string keys to atoms if they match expected metadata keys
          parsed
          |> Enum.reduce(%{}, fn {k, v}, acc ->
            case k do
              "causation_id" -> Map.put(acc, :causation_id, v)
              "correlation_id" -> Map.put(acc, :correlation_id, v)
              "stream_version" -> Map.put(acc, :stream_version, v)
              _ -> Map.put(acc, k, v)
            end
          end)
        {:ok, _} -> %{}
        {:error, _} -> %{}
      end
    rescue
      _ -> %{}
    end
  end
  defp parse_metadata(_), do: %{}

  # Subscription proxy process loop
  defp subscription_loop(metadata) do
    receive do
      {:set_subscription_metadata, new_metadata} ->
        # Update metadata with subscription info from subscribe_to
        updated_metadata = Map.merge(metadata, new_metadata)
        subscription_loop(updated_metadata)
        
      :unsubscribe ->
        # Clean up the ExESDB subscription
        %{name: subscription_name, type: type, selector: selector, store: store} = metadata
        API.remove_subscription(store, type, selector, subscription_name)
        # Process exits naturally
        
      {:events, [%ExESDB.Schema.EventRecord{} = event_record]} ->
        # Convert ExESDB event to Commanded RecordedEvent format
        %{subscriber: subscriber, selector: selector} = metadata
        
        Logger.info("ADAPTER PROXY [#{selector}]: Received EventRecord #{event_record.event_type} for stream #{event_record.event_stream_id}")
        Logger.debug("Adapter proxy converting EventRecord to RecordedEvent for subscriber #{inspect(subscriber)}")
        
        # Parse metadata and ensure it has the required structure for Mapper
        parsed_metadata = parse_metadata(event_record.metadata)
        
        # Ensure metadata has the required keys for Mapper.to_recorded_event
        normalized_metadata = %{
          stream_version: event_record.event_number,
          correlation_id: Map.get(parsed_metadata, :correlation_id),
          causation_id: Map.get(parsed_metadata, :causation_id)
        }
        
        # Create a normalized event record for the Mapper
        normalized_event_record = %{event_record | metadata: normalized_metadata}
        
        # Use the official Mapper to ensure consistent format
        recorded_event = Mapper.to_recorded_event(normalized_event_record)
        
        Logger.info("ADAPTER PROXY [#{selector}]: Sending converted event #{recorded_event.event_type} to subscriber #{inspect(subscriber)}")
        # Send events to subscriber in Commanded format
        send(subscriber, {:events, [recorded_event]})
        Logger.info("ADAPTER PROXY [#{selector}]: Event sent successfully")
        
        subscription_loop(metadata)
        
      {:events, events} when is_list(events) ->
        # Handle multiple events or already converted events
        %{subscriber: subscriber} = metadata
        
        converted_events = Enum.map(events, fn
          %ExESDB.Schema.EventRecord{} = event_record ->
            parsed_metadata = parse_metadata(event_record.metadata)
            %Commanded.EventStore.RecordedEvent{
              event_id: event_record.event_id,
              event_number: event_record.event_number,
              stream_id: event_record.event_stream_id,
              stream_version: event_record.event_number,
              causation_id: Map.get(parsed_metadata, :causation_id),
              correlation_id: Map.get(parsed_metadata, :correlation_id),
              event_type: event_record.event_type,
              data: event_record.data,
              metadata: parsed_metadata,
              created_at: event_record.created
            }
          
          %Commanded.EventStore.RecordedEvent{} = recorded_event ->
            # Already in correct format
            recorded_event
        end)
        
        # Send events to subscriber in Commanded format
        send(subscriber, {:events, converted_events})
        
        subscription_loop(metadata)
        
      {:event_emitted, %ExESDB.Schema.EventRecord{} = event_record} ->
        # Handle legacy event_emitted format for backwards compatibility
        %{subscriber: subscriber} = metadata
        
        Logger.debug("Adapter proxy converting legacy event_emitted to RecordedEvent")
        
        parsed_metadata = parse_metadata(event_record.metadata)
        recorded_event = %Commanded.EventStore.RecordedEvent{
          event_id: event_record.event_id,
          event_number: event_record.event_number,
          stream_id: event_record.event_stream_id,
          stream_version: event_record.event_number,
          causation_id: Map.get(parsed_metadata, :causation_id),
          correlation_id: Map.get(parsed_metadata, :correlation_id),
          event_type: event_record.event_type,
          data: event_record.data,
          metadata: parsed_metadata,
          created_at: event_record.created
        }
        
        send(subscriber, {:events, [recorded_event]})
        subscription_loop(metadata)
        
      {:events, [%ExESDB.Schema.EventRecord{} = event_record]} when is_map(event_record) ->
        # Catch any ExESDB events that don't match the exact pattern above
        %{subscriber: subscriber} = metadata
        
        Logger.warning("Adapter proxy caught unmatched EventRecord, converting to RecordedEvent")
        
        parsed_metadata = parse_metadata(event_record.metadata)
        recorded_event = %Commanded.EventStore.RecordedEvent{
          event_id: event_record.event_id,
          event_number: event_record.event_number,
          stream_id: event_record.event_stream_id,
          stream_version: event_record.event_number,
          causation_id: Map.get(parsed_metadata, :causation_id),
          correlation_id: Map.get(parsed_metadata, :correlation_id),
          event_type: event_record.event_type,
          data: event_record.data,
          metadata: parsed_metadata,
          created_at: event_record.created
        }
        
        send(subscriber, {:events, [recorded_event]})
        subscription_loop(metadata)
        
      message ->
        # Forward any other messages to the actual subscriber
        %{subscriber: subscriber, selector: selector} = metadata
        Logger.info("ADAPTER PROXY [#{selector}]: Received unknown message: #{inspect(message)}")
        send(subscriber, message)
        subscription_loop(metadata)
    end
  end
end
