defmodule RegulateGreenhouse.Infrastructure.EventDeduplicator do
  @moduledoc """
  Event deduplication service to prevent processing duplicate events during 
  cluster failovers or subscription restarts.

  This module maintains a cache of recently processed event IDs with TTL
  to detect and skip duplicate events.
  """

  use GenServer
  require Logger

  @cache_name :greenhouse_event_dedup
  # 10 minutes
  @default_ttl :timer.minutes(10)
  # 5 minutes
  @cleanup_interval :timer.minutes(5)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an event has already been processed.
  Returns true if the event is a duplicate, false if it's new.
  """
  def is_duplicate?(event_id) do
    case Cachex.get(@cache_name, event_id) do
      {:ok, nil} -> false
      {:ok, _} -> true
      # Assume it's new if cache error
      {:error, _} -> false
    end
  end

  @doc """
  Mark an event as processed.
  """
  def mark_processed(event_id) do
    case Cachex.put(@cache_name, event_id, :processed) do
      {:ok, true} ->
        # Set expiration separately
        Cachex.expire(@cache_name, event_id, @default_ttl)
        :ok

      {:error, reason} ->
        Logger.warning("Failed to mark event #{event_id} as processed: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Process an event with deduplication check.
  Returns {:ok, result} if the event was processed, or {:duplicate, event_id} if it was a duplicate.
  """
  def process_with_dedup(event_id, processor_fun) when is_function(processor_fun, 0) do
    if is_duplicate?(event_id) do
      Logger.debug("Skipping duplicate event #{event_id}")
      {:duplicate, event_id}
    else
      case processor_fun.() do
        result ->
          mark_processed(event_id)
          {:ok, result}
      end
    end
  end

  @doc """
  Get current cache statistics.
  """
  def stats do
    case Cachex.stats(@cache_name) do
      {:ok, stats} ->
        stats

      {:error, reason} ->
        #        Logger.warning("Failed to get deduplication cache stats: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Clear all cached event IDs.
  """
  def clear do
    case Cachex.clear(@cache_name) do
      {:ok, count} ->
        Logger.info("Cleared #{count} entries from event deduplication cache")
        :ok

      {:error, reason} ->
        Logger.error("Failed to clear event deduplication cache: #{inspect(reason)}")
        :error
    end
  end

  # Server Implementation

  @impl GenServer
  def init(_opts) do
    # Start the cache if it doesn't exist
    case Cachex.start_link(@cache_name) do
      {:ok, _pid} ->
        Logger.info("EventDeduplicator cache started successfully")
        {:ok, %{}}

      {:error, {:already_started, _pid}} ->
        Logger.info("EventDeduplicator cache already running")
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("Failed to start EventDeduplicator cache: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
