defmodule RegulateGreenhouse.CacheRebuildService do
  @moduledoc """
  Service for rebuilding greenhouse read model caches from ExESDB event streams.

  This service reads all events from the event store and replays them through
  the existing event handlers to reconstruct the cache state. This is useful
  for:
  - Application restarts when cache is empty
  - Cache corruption recovery
  - Migrating to new cache schemas
  - Development and testing scenarios
  """

  require Logger

  alias RegulateGreenhouse.Projections.Handlers.{
    GreenhouseEventHandler,
    TemperatureEventHandler,
    HumidityEventHandler,
    LightEventHandler
  }

  alias ExESDBGater.API

  @store_id :reg_gh
  @cache_name :greenhouse_read_models
  @batch_size 100

  @doc """
  Rebuild the entire cache from event streams.

  This will:
  1. Clear the existing cache
  2. Read all streams from the store
  3. Replay all events through the appropriate handlers
  4. Return statistics about the rebuild process
  """
  @spec rebuild_cache() :: {:ok, map()} | {:error, term()}
  def rebuild_cache do
    Logger.info("CacheRebuildService: Starting cache rebuild process")
    start_time = System.monotonic_time(:millisecond)

    try do
      # Step 1: Clear existing cache
      case clear_cache() do
        :ok ->
          Logger.info("CacheRebuildService: Cache cleared successfully")

        {:error, reason} ->
          Logger.error("CacheRebuildService: Failed to clear cache: #{inspect(reason)}")
          throw({:error, {:cache_clear_failed, reason}})
      end

      # Step 2: Get all streams
      Logger.debug(
        "CacheRebuildService: Calling API.get_streams with store_id: #{inspect(@store_id)}"
      )

      case API.get_streams(@store_id) do
        {:ok, streams} when is_list(streams) ->
          stream_count = length(streams)
          Logger.info("CacheRebuildService: Found #{stream_count} streams to rebuild")
          Logger.debug("CacheRebuildService: Stream list: #{inspect(streams)}")

          # Step 3: Process each stream
          stats = process_streams(streams)

          end_time = System.monotonic_time(:millisecond)
          duration_ms = end_time - start_time

          final_stats =
            Map.merge(stats, %{
              duration_ms: duration_ms,
              streams_processed: stream_count,
              cache_size: get_cache_size()
            })

          Logger.info(
            "CacheRebuildService: Cache rebuild completed successfully in #{duration_ms}ms"
          )

          Logger.info("CacheRebuildService: Final stats: #{inspect(final_stats)}")

          {:ok, final_stats}

        {:ok, streams} ->
          Logger.error(
            "CacheRebuildService: API.get_streams returned non-list: #{inspect(streams)}"
          )

          {:error, {:invalid_streams_response, streams}}

        {:error, reason} ->
          Logger.error("CacheRebuildService: Failed to get streams: #{inspect(reason)}")
          {:error, {:get_streams_failed, reason}}
      end
    rescue
      e ->
        Logger.error("CacheRebuildService: Unexpected error during rebuild: #{inspect(e)}")

        Logger.error(
          "CacheRebuildService: Error stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        {:error, {:unexpected_error, e}}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Rebuild cache for specific streams only.
  """
  @spec rebuild_cache_for_streams([String.t()]) :: {:ok, map()} | {:error, term()}
  def rebuild_cache_for_streams(stream_ids) when is_list(stream_ids) do
    Logger.info(
      "CacheRebuildService: Starting partial cache rebuild for streams: #{inspect(stream_ids)}"
    )

    start_time = System.monotonic_time(:millisecond)

    try do
      # Clear cache entries for these specific streams
      Enum.each(stream_ids, fn stream_id ->
        greenhouse_id = extract_greenhouse_id(stream_id)

        if greenhouse_id do
          case Cachex.del(@cache_name, greenhouse_id) do
            {:ok, _} ->
              :ok

            error ->
              Logger.warning(
                "CacheRebuildService: Failed to clear cache for #{greenhouse_id}: #{inspect(error)}"
              )
          end
        end
      end)

      # Process specified streams
      stats = process_streams(stream_ids)

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      final_stats =
        Map.merge(stats, %{
          duration_ms: duration_ms,
          streams_processed: length(stream_ids),
          cache_size: get_cache_size()
        })

      Logger.info("CacheRebuildService: Partial cache rebuild completed in #{duration_ms}ms")
      {:ok, final_stats}
    rescue
      e ->
        Logger.error("CacheRebuildService: Error during partial rebuild: #{inspect(e)}")
        {:error, {:rebuild_failed, e}}
    end
  end

  @doc """
  Get rebuild statistics without performing a rebuild.
  """
  @spec get_rebuild_info() :: {:ok, map()} | {:error, term()}
  def get_rebuild_info do
    case API.get_streams(@store_id) do
      {:ok, streams} ->
        stream_info =
          Enum.map(streams, fn stream_id ->
            case API.get_version(@store_id, stream_id) do
              {:ok, version} when version >= 0 ->
                %{stream_id: stream_id, event_count: version + 1}

              {:ok, -1} ->
                %{stream_id: stream_id, event_count: 0}

              {:error, _} ->
                %{stream_id: stream_id, event_count: 0}
            end
          end)

        total_events = stream_info |> Enum.map(& &1.event_count) |> Enum.sum()

        info = %{
          total_streams: length(streams),
          total_events: total_events,
          current_cache_size: get_cache_size(),
          estimated_rebuild_time_ms: estimate_rebuild_time(total_events),
          streams: stream_info
        }

        {:ok, info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp process_streams(stream_ids) do
    initial_stats = %{
      events_processed: 0,
      events_failed: 0,
      greenhouses_created: 0,
      errors: []
    }

    try do
      stream_ids
      |> Enum.reduce(initial_stats, fn stream_id, acc_stats ->
        try do
          case process_single_stream(stream_id) do
            {:ok, stream_stats} ->
              %{
                events_processed: acc_stats.events_processed + stream_stats.events_processed,
                events_failed: acc_stats.events_failed + stream_stats.events_failed,
                greenhouses_created:
                  acc_stats.greenhouses_created + stream_stats.greenhouses_created,
                errors: acc_stats.errors ++ stream_stats.errors
              }

            {:error, reason} ->
              Logger.error(
                "CacheRebuildService: Failed to process stream #{stream_id}: #{inspect(reason)}"
              )

              %{acc_stats | errors: acc_stats.errors ++ [{stream_id, reason}]}
          end
        rescue
          e ->
            Logger.error(
              "CacheRebuildService: Exception processing stream #{stream_id}: #{inspect(e)}"
            )

            Logger.error(
              "CacheRebuildService: Exception stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}"
            )

            %{acc_stats | errors: acc_stats.errors ++ [{stream_id, {:exception, e}}]}
        end
      end)
    rescue
      e ->
        Logger.error("CacheRebuildService: Exception in process_streams: #{inspect(e)}")

        Logger.error(
          "CacheRebuildService: Exception stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        %{initial_stats | errors: [{:process_streams_exception, e}]}
    end
  end

  defp process_single_stream(stream_id) do
    Logger.debug("CacheRebuildService: Processing stream #{stream_id}")

    # Get the greenhouse ID from the stream
    greenhouse_id = extract_greenhouse_id(stream_id)

    case greenhouse_id do
      nil ->
        Logger.warning(
          "CacheRebuildService: Cannot extract greenhouse ID from stream #{stream_id}"
        )

        {:ok, %{events_processed: 0, events_failed: 0, greenhouses_created: 0, errors: []}}

      _ ->
        case API.get_version(@store_id, stream_id) do
          {:ok, latest_version} when latest_version >= 0 ->
            # ExESDB uses 0-based indexing consistently
            Logger.info(
              "CacheRebuildService: Stream #{stream_id} has latest_version: #{latest_version}"
            )

            # Read events from version 0 to latest_version (inclusive)
            # Total events = latest_version + 1 (since 0-based)
            total_events = latest_version + 1
            process_stream_events(stream_id, greenhouse_id, total_events)

          {:ok, -1} ->
            # Empty stream
            Logger.debug("CacheRebuildService: Stream #{stream_id} is empty")
            {:ok, %{events_processed: 0, events_failed: 0, greenhouses_created: 0, errors: []}}

          {:error, reason} ->
            Logger.error(
              "CacheRebuildService: Failed to get version for stream #{stream_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  defp process_stream_events(stream_id, greenhouse_id, total_events) do
    Logger.debug("CacheRebuildService: Processing #{total_events} events for stream #{stream_id}")

    stats = %{events_processed: 0, events_failed: 0, greenhouses_created: 0, errors: []}

    # Process events in batches to avoid memory issues
    # ExESDB uses 0-based indexing consistently, so start from version 0
    if total_events <= 0 do
      {:ok, stats}
    else
      read_events_in_batches(stream_id, greenhouse_id, total_events, 0, stats)
    end
  end

  defp read_events_in_batches(stream_id, greenhouse_id, total_events, current_version, acc_stats) do
    # For 0-based indexing: if latest_version is 4, total_events is 5, we read versions 0,1,2,3,4
    # So we continue while current_version < total_events

    if current_version >= total_events do
      {:ok, acc_stats}
    else
      remaining_events = total_events - current_version
      batch_size = min(@batch_size, remaining_events)

      Logger.debug(
        "CacheRebuildService: Reading batch from #{stream_id}, start_version: #{current_version}, count: #{batch_size}"
      )

      case API.get_events(@store_id, stream_id, current_version, batch_size, :forward) do
        {:ok, events} ->
          batch_stats = process_event_batch(events, greenhouse_id)

          combined_stats = %{
            events_processed: acc_stats.events_processed + batch_stats.events_processed,
            events_failed: acc_stats.events_failed + batch_stats.events_failed,
            greenhouses_created: acc_stats.greenhouses_created + batch_stats.greenhouses_created,
            errors: acc_stats.errors ++ batch_stats.errors
          }

          # Continue reading the next batch
          next_version = current_version + length(events)

          read_events_in_batches(
            stream_id,
            greenhouse_id,
            total_events,
            next_version,
            combined_stats
          )

        {:error, reason} ->
          Logger.error(
            "CacheRebuildService: Failed to get events batch for #{stream_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp process_event_batch(events, greenhouse_id) do
    events
    |> Enum.reduce(
      %{events_processed: 0, events_failed: 0, greenhouses_created: 0, errors: []},
      fn event, stats ->
        case process_single_event(event, greenhouse_id) do
          {:ok, :greenhouse_created} ->
            %{
              stats
              | events_processed: stats.events_processed + 1,
                greenhouses_created: stats.greenhouses_created + 1
            }

          {:ok, _} ->
            %{stats | events_processed: stats.events_processed + 1}

          {:error, reason} ->
            Logger.warning("CacheRebuildService: Failed to process event: #{inspect(reason)}")
            %{stats | events_failed: stats.events_failed + 1, errors: stats.errors ++ [reason]}
        end
      end
    )
  end

  defp process_single_event(event, greenhouse_id) do
    # Transform ExESDB.Schema.EventRecord to the format expected by event handlers
    {event_type, normalized_event} =
      case event do
        %ExESDB.Schema.EventRecord{event_type: type, data: data} ->
          # Convert EventRecord to the map format expected by handlers
          {type, %{event_type: type, data: data}}

        %{"event_type" => type} = map_event ->
          {type, map_event}

        %{event_type: type} = map_event ->
          {type, map_event}

        _ ->
          {nil, event}
      end

    try do
      case event_type do
        "initialized:v1" ->
          GreenhouseEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :greenhouse_created}

        "desired_temperature_set:v1" ->
          TemperatureEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :temperature_set}

        "temperature_measured:v1" ->
          TemperatureEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :temperature_measured}

        "desired_humidity_set:v1" ->
          HumidityEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :humidity_set}

        "humidity_measured:v1" ->
          HumidityEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :humidity_measured}

        "desired_light_set:v1" ->
          LightEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :light_set}

        "light_measured:v1" ->
          LightEventHandler.handle_event(normalized_event, greenhouse_id)
          {:ok, :light_measured}

        _ ->
          {:ok, :unknown_event}
      end
    rescue
      e ->
        Logger.error("CacheRebuildService: Error processing event #{event_type}: #{inspect(e)}")
        {:error, {:event_processing_failed, event_type, e}}
    end
  end

  # Extract greenhouse ID from stream name (assuming format like "regulate_greenhouse_greenhouse1")
  defp extract_greenhouse_id(stream_id) when is_binary(stream_id) do
    try do
      case String.split(stream_id, "_") do
        parts when length(parts) >= 3 ->
          greenhouse_id = List.last(parts)

          if greenhouse_id != "" and greenhouse_id != nil do
            greenhouse_id
          else
            Logger.warning("CacheRebuildService: Empty greenhouse_id extracted from #{stream_id}")
            nil
          end

        _ ->
          Logger.warning(
            "CacheRebuildService: Stream #{stream_id} doesn't match expected pattern"
          )

          nil
      end
    rescue
      e ->
        Logger.error(
          "CacheRebuildService: Error extracting greenhouse_id from #{stream_id}: #{inspect(e)}"
        )

        nil
    end
  end

  defp extract_greenhouse_id(stream_id) do
    Logger.error("CacheRebuildService: Invalid stream_id type: #{inspect(stream_id)}")
    nil
  end

  defp clear_cache do
    case Cachex.clear(@cache_name) do
      {:ok, _count} -> :ok
      error -> error
    end
  end

  defp get_cache_size do
    case Cachex.size(@cache_name) do
      {:ok, size} -> size
      {:error, _} -> 0
    end
  end

  defp estimate_rebuild_time(total_events) do
    # Rough estimate: ~1ms per event processing
    total_events * 1
  end
end
