defmodule RegulateGreenhouse.Projections.EventTypeProjection do
  @moduledoc """
  Individual event type projection worker that subscribes to specific event types
  and delegates handling to the appropriate handler module.
  
  This worker:
  - Subscribes to events by event type pattern
  - Uses circuit breaker protection
  - Implements event deduplication
  - Routes events to greenhouse-specific handlers based on stream_id
  """
  
  use GenServer
  require Logger
  
  alias RegulateGreenhouse.Infrastructure.{CircuitBreaker, EventDeduplicator, SubscriptionManager}
  alias ExESDBGater.API
  
  defstruct [
    :event_type,
    :handler_module,
    :subscription,
    :subscription_proxy,
    :circuit_breaker_name,
    :name
  ]
  
  def start_link(opts) do
    event_type = Keyword.fetch!(opts, :event_type)
    handler_module = Keyword.fetch!(opts, :handler_module)
    name = Keyword.fetch!(opts, :name)
    
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @impl GenServer
  def init(opts) do
    event_type = Keyword.fetch!(opts, :event_type)
    handler_module = Keyword.fetch!(opts, :handler_module)
    name = Keyword.fetch!(opts, :name)
    
    circuit_breaker_name = :"#{event_type}_circuit_breaker"
    
    # Start circuit breaker for this event type
    case start_circuit_breaker(circuit_breaker_name) do
      :ok -> :ok
      {:error, {:already_started, _}} -> :ok  # Already exists
      {:error, reason} ->
        Logger.error("EventTypeProjection[#{event_type}]: Failed to start circuit breaker: #{inspect(reason)}")
        {:stop, reason}
    end
    
    state = %__MODULE__{
      event_type: event_type,
      handler_module: handler_module,
      subscription: nil,
      subscription_proxy: nil,
      circuit_breaker_name: circuit_breaker_name,
      name: name
    }
    
    # Subscribe to events of this type
    case create_subscription(state) do
      {:ok, {subscription_name, proxy_pid}} ->
        updated_state = %{state | subscription: subscription_name, subscription_proxy: proxy_pid}
        
        # Register with subscription manager for monitoring
        register_for_monitoring(updated_state)
        
        Logger.info("EventTypeProjection[#{event_type}]: Started successfully")
        {:ok, updated_state}
      
      {:error, reason} ->
        Logger.error("EventTypeProjection[#{event_type}]: Failed to create subscription: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl GenServer
  def handle_info({:events, events}, state) when is_list(events) do
    require Logger
    Logger.info("EventTypeProjection[#{state.event_type}]: Received #{length(events)} events")
    
    # Process each event with protection
    Enum.each(events, fn event ->
      Logger.info("EventTypeProjection[#{state.event_type}]: Processing event #{inspect(event)}")
      process_event_with_protection(event, state)
    end)
    
    {:noreply, state}
  end
  
  def handle_info(msg, state) do
    require Logger
    Logger.warning("EventTypeProjection[#{state.event_type}]: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl GenServer
  def terminate(reason, state) do
    Logger.info("EventTypeProjection[#{state.event_type}]: Terminating: #{inspect(reason)}")
    
    # Clean up subscription and proxy
    if state.subscription do
      try do
        store = :reg_gh
        API.remove_subscription(store, :by_event_type, state.event_type, state.subscription)
      rescue
        _ -> :ok  # Ignore errors during cleanup
      end
    end
    
    # Clean up proxy process
    if state.subscription_proxy do
      try do
        Process.exit(state.subscription_proxy, :normal)
      rescue
        _ -> :ok  # Ignore errors during cleanup
      end
    end
    
    # Unregister from monitoring
    SubscriptionManager.unregister_subscription("#{state.event_type}_projection")
    
    :ok
  end
  
  # Private functions
  
  defp start_circuit_breaker(name) do
    case CircuitBreaker.start_link([
      name: name,
      config: %{
        failure_threshold: 3,
        recovery_timeout: 30_000,  # 30 seconds
        reset_timeout: 15_000      # 15 seconds
      }
    ]) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp create_subscription(state) do
    # Subscribe to events by event type using ex-esdb API
    store = :reg_gh  # Use the configured store ID
    subscription_name = "#{state.event_type}_projection"
    
    # Create a proxy process that can handle ExESDB subscription messages properly
    # This matches the pattern used in the Commanded adapter
    subscriber = self()
    proxy_pid = spawn(fn ->
      subscription_proxy_loop(%{
        name: subscription_name,
        subscriber: subscriber,
        event_type: state.event_type,
        store: store
      })
    end)
    
    case API.save_subscription(
      store,
      :by_event_type,
      state.event_type,
      subscription_name,
      0,  # Start from beginning
      proxy_pid  # Use proxy process as subscriber
    ) do
      :ok ->
        Logger.info("EventTypeProjection[#{state.event_type}]: Subscribed to event type #{state.event_type} via proxy #{inspect(proxy_pid)}")
        {:ok, {subscription_name, proxy_pid}}
      
      {:error, reason} ->
        # Clean up proxy if subscription failed
        Process.exit(proxy_pid, :kill)
        Logger.error("EventTypeProjection[#{state.event_type}]: Failed to subscribe to event type #{state.event_type}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp register_for_monitoring(state) do
    restart_fun = fn ->
      # Restart this projection
      case GenServer.start_link(__MODULE__, [
        event_type: state.event_type,
        handler_module: state.handler_module,
        name: state.name
      ], name: state.name) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        error -> error
      end
    end
    
    SubscriptionManager.register_subscription(
      "#{state.event_type}_projection",
      self(),
      restart_fun
    )
  end
  
  defp process_event_with_protection(event, state) do
    # Extract event ID for deduplication
    event_id = extract_event_id(event)
    
    case EventDeduplicator.process_with_dedup(event_id, fn ->
      # Process with circuit breaker protection
      case CircuitBreaker.call(state.circuit_breaker_name, fn ->
        # Extract greenhouse_id from stream_id and delegate to handler
        greenhouse_id = extract_greenhouse_id(event.event_stream_id)
        
        if greenhouse_id do
          # Convert ExESDB.Schema.EventRecord to a format our handlers expect
          converted_event = %{
            data: event.data,
            event_type: event.event_type,
            stream_id: event.event_stream_id,
            event_number: event.event_number,
            created: event.created
          }
          
          state.handler_module.handle_event(converted_event, greenhouse_id)
        else
          Logger.warning("EventTypeProjection[#{state.event_type}]: Could not extract greenhouse_id from stream_id: #{event.event_stream_id}")
          :ok
        end
      end) do
        {:ok, result} -> result
        
        {:error, {:circuit_breaker, reason}} ->
          Logger.error("EventTypeProjection[#{state.event_type}]: Circuit breaker prevented processing: #{inspect(reason)}")
          :error
        
        {:error, :circuit_breaker_open} ->
          Logger.warning("EventTypeProjection[#{state.event_type}]: Circuit breaker is open, skipping event")
          :error
      end
    end) do
      {:ok, _result} -> :ok
      {:duplicate, _} -> :ok
    end
  end
  
  defp extract_event_id(event) do
    case event do
      %{event_id: id} -> id
      %{id: id} -> id
      _ -> "#{event.event_type}_#{event.event_stream_id}_#{event.event_number}"
    end
  end
  
  defp extract_greenhouse_id(stream_id) do
    # Extract greenhouse_id from stream_id
    # Stream format: "regulate_greenhouse_{greenhouse_id}"
    case String.split(stream_id, "_", parts: 3) do
      ["regulate", "greenhouse", greenhouse_id] when greenhouse_id != "" ->
        greenhouse_id
      
      _ ->
        # Log for debugging and return nil if pattern doesn't match
        Logger.warning("Could not extract greenhouse_id from stream_id: #{stream_id}")
        nil
    end
  end
  
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  # Subscription proxy process loop - handles ExESDB event messages and forwards to EventTypeProjection
  defp subscription_proxy_loop(metadata) do
    receive do
      {:events, [%ExESDB.Schema.EventRecord{} = event_record]} ->
        # Convert ExESDB event to our internal format and forward to subscriber
        %{subscriber: subscriber, event_type: event_type} = metadata
        
        Logger.info("SubscriptionProxy[#{event_type}]: Received EventRecord #{event_record.event_type} for stream #{event_record.event_stream_id}")
        
        # Only forward events that match our event type
        if event_record.event_type == event_type do
          Logger.info("SubscriptionProxy[#{event_type}]: Forwarding matching event to subscriber #{inspect(subscriber)}")
          send(subscriber, {:events, [event_record]})
        else
          Logger.debug("SubscriptionProxy[#{event_type}]: Ignoring non-matching event type #{event_record.event_type}")
        end
        
        subscription_proxy_loop(metadata)
        
      {:events, events} when is_list(events) ->
        # Handle multiple events
        %{subscriber: subscriber, event_type: event_type} = metadata
        
        Logger.info("SubscriptionProxy[#{event_type}]: Received #{length(events)} events")
        
        # Filter to only matching event types
        matching_events = Enum.filter(events, fn
          %ExESDB.Schema.EventRecord{event_type: ^event_type} -> true
          _ -> false
        end)
        
        if length(matching_events) > 0 do
          Logger.info("SubscriptionProxy[#{event_type}]: Forwarding #{length(matching_events)} matching events")
          send(subscriber, {:events, matching_events})
        end
        
        subscription_proxy_loop(metadata)
        
      :unsubscribe ->
        # Clean up the subscription
        %{name: subscription_name, event_type: event_type, store: store} = metadata
        Logger.info("SubscriptionProxy[#{event_type}]: Unsubscribing #{subscription_name}")
        API.remove_subscription(store, :by_event_type, event_type, subscription_name)
        # Process exits naturally
        
      message ->
        # Log unknown messages but continue
        %{event_type: event_type} = metadata
        Logger.warning("SubscriptionProxy[#{event_type}]: Received unknown message: #{inspect(message)}")
        subscription_proxy_loop(metadata)
    end
  end
end
