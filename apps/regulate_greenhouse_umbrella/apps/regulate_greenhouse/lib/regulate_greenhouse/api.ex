defmodule RegulateGreenhouse.API do
  @moduledoc """
  Public API for the RegulateGreenhouse Commanded application.

  This module provides functions to dispatch commands and query
  the greenhouse regulation domain.
  """

  alias RegulateGreenhouse.CommandedApp

  alias RegulateGreenhouse.Commands.{
    InitializeGreenhouse,
    SetTemperature,
    SetHumidity,
    SetLight,
    MeasureTemperature,
    MeasureHumidity,
    MeasureLight
  }

  @doc """
  Creates a new greenhouse.
  """
  @spec create_greenhouse(String.t(), String.t(), String.t(), float() | nil, float() | nil) ::
          :ok | {:error, term()}
  def create_greenhouse(
        greenhouse_id,
        name,
        location,
        target_temperature \\ nil,
        target_humidity \\ nil
      ) do
    require Logger

    command = %InitializeGreenhouse{
      greenhouse_id: greenhouse_id,
      name: name,
      location: location,
      target_temperature: target_temperature,
      target_humidity: target_humidity
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        :ok

      error ->
        Logger.error(
          "API: Failed to dispatch InitializeGreenhouse for #{greenhouse_id}: #{inspect(error)}"
        )

        error
    end
  end

  @doc """
  Initializes a greenhouse with sensor readings.
  """
  @spec initialize_greenhouse(String.t(), float(), float(), float()) :: :ok | {:error, term()}
  def initialize_greenhouse(greenhouse_id, temperature, humidity, light) do
    require Logger

    Logger.info(
      "API: Initializing greenhouse #{greenhouse_id} - ONLY CREATING, measurements disabled for debugging"
    )

    # First create the greenhouse
    case create_greenhouse(greenhouse_id, greenhouse_id, "Unknown") do
      :ok ->
        Logger.info(
          "API: Greenhouse #{greenhouse_id} created successfully (measurements disabled)"
        )

        # Measurements temporarily disabled for debugging
        # :timer.sleep(500)
        # Logger.info("API: Starting measurements for #{greenhouse_id}")
        # with :ok <- measure_temperature(greenhouse_id, temperature),
        #      :ok <- measure_humidity(greenhouse_id, humidity),
        #      :ok <- measure_light(greenhouse_id, light) do
        #   Logger.info("API: Completed initialization for #{greenhouse_id}")
        #   :ok
        # end
        Logger.info("API: Completed initialization for #{greenhouse_id} (measurements disabled)")
        :ok

      error ->
        error
    end
  end

  @doc """
  Sets the target temperature for a greenhouse.
  """
  @spec set_temperature(String.t(), float(), String.t() | nil) :: :ok | {:error, term()}
  def set_temperature(greenhouse_id, target_temperature, set_by \\ nil) do
    require Logger

    Logger.info(
      "API: Setting temperature for #{greenhouse_id} to #{target_temperature}°C (set_by: #{set_by})"
    )

    command = %SetTemperature{
      greenhouse_id: greenhouse_id,
      target_temperature: target_temperature,
      set_by: set_by
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        Logger.info("API: Successfully set temperature for #{greenhouse_id}")
        :ok

      error ->
        Logger.error("API: Failed to set temperature for #{greenhouse_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Sets the desired temperature for a greenhouse.
  """
  @spec set_desired_temperature(String.t(), float()) :: :ok | {:error, term()}
  def set_desired_temperature(greenhouse_id, temperature) do
    set_temperature(greenhouse_id, temperature)
  end

  @doc """
  Sets the target humidity for a greenhouse.
  """
  @spec set_humidity(String.t(), float(), String.t() | nil) :: :ok | {:error, term()}
  def set_humidity(greenhouse_id, target_humidity, set_by \\ nil) do
    require Logger

    Logger.info(
      "API: Setting humidity for #{greenhouse_id} to #{target_humidity}% (set_by: #{set_by})"
    )

    command = %SetHumidity{
      greenhouse_id: greenhouse_id,
      target_humidity: target_humidity,
      set_by: set_by
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        Logger.info("API: Successfully set humidity for #{greenhouse_id}")
        :ok

      error ->
        Logger.error("API: Failed to set humidity for #{greenhouse_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Sets the desired humidity for a greenhouse.
  """
  @spec set_desired_humidity(String.t(), float()) :: :ok | {:error, term()}
  def set_desired_humidity(greenhouse_id, humidity) do
    set_humidity(greenhouse_id, humidity)
  end

  @doc """
  Sets the desired light level for a greenhouse.
  """
  @spec set_desired_light(String.t(), float()) :: :ok | {:error, term()}
  def set_desired_light(greenhouse_id, light) do
    require Logger
    Logger.info("API: Setting light for #{greenhouse_id} to #{light} lumens")

    command = %SetLight{
      greenhouse_id: greenhouse_id,
      target_light: light
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        Logger.info("API: Successfully set light for #{greenhouse_id}")
        :ok

      error ->
        Logger.error("API: Failed to set light for #{greenhouse_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Records a temperature measurement for a greenhouse.
  """
  @spec measure_temperature(String.t(), float()) :: :ok | {:error, term()}
  def measure_temperature(greenhouse_id, temperature) do
    require Logger
    Logger.info("API: Recording temperature measurement for #{greenhouse_id}: #{temperature}°C")

    command = %MeasureTemperature{
      greenhouse_id: greenhouse_id,
      temperature: temperature,
      measured_at: DateTime.utc_now()
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        Logger.info("API: Successfully recorded temperature measurement for #{greenhouse_id}")
        :ok

      error ->
        Logger.error(
          "API: Failed to record temperature measurement for #{greenhouse_id}: #{inspect(error)}"
        )

        error
    end
  end

  @doc """
  Records a humidity measurement for a greenhouse.
  """
  @spec measure_humidity(String.t(), float()) :: :ok | {:error, term()}
  def measure_humidity(greenhouse_id, humidity) do
    require Logger
    Logger.info("API: Recording humidity measurement for #{greenhouse_id}: #{humidity}%")

    command = %MeasureHumidity{
      greenhouse_id: greenhouse_id,
      humidity: humidity,
      measured_at: DateTime.utc_now()
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        Logger.info("API: Successfully recorded humidity measurement for #{greenhouse_id}")
        :ok

      error ->
        Logger.error(
          "API: Failed to record humidity measurement for #{greenhouse_id}: #{inspect(error)}"
        )

        error
    end
  end

  @doc """
  Records a light measurement for a greenhouse.
  """
  @spec measure_light(String.t(), float()) :: :ok | {:error, term()}
  def measure_light(greenhouse_id, light) do
    require Logger
    Logger.info("API: Recording light measurement for #{greenhouse_id}: #{light} lumens")

    command = %MeasureLight{
      greenhouse_id: greenhouse_id,
      light: light,
      measured_at: DateTime.utc_now()
    }

    case CommandedApp.dispatch_command(command) do
      :ok ->
        Logger.info("API: Successfully recorded light measurement for #{greenhouse_id}")
        :ok

      error ->
        Logger.error(
          "API: Failed to record light measurement for #{greenhouse_id}: #{inspect(error)}"
        )

        error
    end
  end

  @doc """
  Lists all known greenhouse IDs.
  """
  @spec list_greenhouses() :: [String.t()]
  def list_greenhouses do
    RegulateGreenhouse.CacheService.list_greenhouses()
    |> Enum.map(& &1.greenhouse_id)
  end

  @doc """
  Gets the current state of a greenhouse.
  """
  @spec get_greenhouse_state(String.t()) :: {:ok, map()} | {:error, term()}
  def get_greenhouse_state(greenhouse_id) do
    case RegulateGreenhouse.CacheService.get_greenhouse(greenhouse_id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, read_model} ->
        {:ok,
         %{
           current_temperature: read_model.current_temperature || 0,
           current_humidity: read_model.current_humidity || 0,
           current_light: read_model.current_light || 0,
           desired_temperature: read_model.target_temperature,
           desired_humidity: read_model.target_humidity,
           desired_light: read_model.target_light,
           last_updated: read_model.updated_at,
           event_count: read_model.event_count,
           status: read_model.status
         }}

      error ->
        error
    end
  end

  @doc """
  Gets recent events for a greenhouse.
  """
  @spec get_greenhouse_events(String.t(), integer()) :: [map()] | nil
  def get_greenhouse_events(greenhouse_id, limit) do
    require Logger

    # Get the stream prefix from configuration
    event_store_config =
      Application.get_env(:regulate_greenhouse, RegulateGreenhouse.CommandedApp)[:event_store]

    stream_prefix = Keyword.get(event_store_config, :stream_prefix, "")
    store_id = Keyword.get(event_store_config, :store_id, :default)

    # Construct the event stream ID using the configured prefix
    event_stream_id = stream_prefix <> greenhouse_id

    Logger.info("API: Constructed event_stream_id for greenhouse #{greenhouse_id}: #{event_stream_id}")

    case ExESDBGater.API.get_events(store_id, event_stream_id, 0, limit) do
      {:ok, events} when is_list(events) ->
        Logger.debug("API: Found #{length(events)} events for greenhouse #{greenhouse_id}")
        
        # Reverse to get most recent first
        events = Enum.reverse(events)
        
        # Convert ExESDB.Schema.EventRecord to a simplified map format for the UI
        converted_events = Enum.map(events, fn event ->
            # Convert struct data to map format for UI consumption
            data =
              case event.data do
                %{__struct__: struct_name} = struct_data ->
                  Logger.debug("API: Converting struct #{struct_name} to map")
                  # Convert struct to map
                  map_data = Map.from_struct(struct_data)
                  Logger.debug("API: Converted data: #{inspect(map_data)}")
                  map_data

                map_data when is_map(map_data) ->
                  Logger.debug("API: Event data is already a map")
                  map_data

                other ->
                  Logger.debug("API: Event data is other type: #{inspect(other)}")
                  other
              end

            %{
              event_id: event.event_id,
              event_type: event.event_type,
              data: data,
              metadata: event.metadata,
              created: event.created,
              event_number: event.event_number
            }
          end)

        converted_events

      {:error, :stream_not_found} ->
        Logger.debug("API: Stream #{event_stream_id} not found")
        []

      {:error, reason} ->
        Logger.warning(
          "API: Failed to read events for stream #{event_stream_id}: #{inspect(reason)}"
        )

        []

      resp ->
        Logger.warning(
          "API: Unexpected response when reading events for stream #{event_stream_id}...response: #{inspect(resp)}"
        )

        []
    end
  end

  @doc """
  Rebuild greenhouse cache from ExESDB event streams.

  This function reads all events from the event store and replays them
  through the existing event handlers to reconstruct the cache state.
  """
  @spec rebuild_cache() :: {:ok, map()} | {:error, term()}
  def rebuild_cache do
    require Logger
    Logger.info("API: Rebuilding cache from ExESDB event streams")

    case RegulateGreenhouse.CacheRebuildService.rebuild_cache() do
      {:ok, stats} ->
        Logger.info("API: Cache rebuild succeeded with stats: #{inspect(stats)}")
        {:ok, stats}

      {:error, error} ->
        Logger.error("API: Cache rebuild failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get the status of cache population on startup.

  Returns information about whether the cache has been populated from
  event streams during application startup.
  """
  @spec get_cache_population_status() :: {:ok, map()} | {:error, term()}
  def get_cache_population_status do
    RegulateGreenhouse.CachePopulationService.population_status()
  end

  @doc """
  Manually trigger cache population.

  This is useful for forcing a cache rebuild outside of the normal
  startup process, such as for testing or manual recovery.
  """
  @spec populate_cache() :: :ok | {:error, term()}
  def populate_cache do
    require Logger
    Logger.info("API: Manually triggering cache population")

    case RegulateGreenhouse.CachePopulationService.populate_cache() do
      :ok ->
        Logger.info("API: Cache population started successfully")
        :ok

      {:error, reason} ->
        Logger.error("API: Failed to start cache population: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Debug function to test event store access directly.
  """
  def debug_event_store(greenhouse_id) do
    require Logger
    
    # Get configuration
    event_store_config = Application.get_env(:regulate_greenhouse, RegulateGreenhouse.CommandedApp)[:event_store]
    stream_prefix = Keyword.get(event_store_config, :stream_prefix, "")
    store_id = Keyword.get(event_store_config, :store_id, :default)
    
    event_stream_id = stream_prefix <> greenhouse_id
    
    Logger.info("DEBUG: Testing event store access")
    Logger.info("DEBUG: store_id: #{inspect(store_id)}")
    Logger.info("DEBUG: stream_prefix: #{inspect(stream_prefix)}")
    Logger.info("DEBUG: event_stream_id: #{inspect(event_stream_id)}")
    
    # Try different API calls to see what works
    Logger.info("DEBUG: Trying stream_backward...")
    case ExESDBGater.API.stream_backward(store_id, event_stream_id, 1000, 30) do
      {:ok, stream} ->
        events = Enum.to_list(stream)
        Logger.info("DEBUG: stream_backward success, found #{length(events)} events")
        Enum.each(events, fn event ->
          Logger.info("DEBUG: Event - type: #{event.event_type}, id: #{event.event_id}")
        end)
        
      error ->
        Logger.error("DEBUG: stream_backward failed: #{inspect(error)}")
    end
    
    # Try list_streams to see what streams exist
    Logger.info("DEBUG: Listing all streams...")
    case ExESDBGater.API.list_streams(store_id) do
      {:ok, streams} ->
        matching_streams = Enum.filter(streams, fn stream -> String.contains?(stream, greenhouse_id) end)
        Logger.info("DEBUG: Found #{length(streams)} total streams")
        Logger.info("DEBUG: Streams matching #{greenhouse_id}: #{inspect(matching_streams)}")
        
      error ->
        Logger.error("DEBUG: list_streams failed: #{inspect(error)}")
    end
    
    :ok
  end

  @doc """
  Debug function to restart event-type projections.
  """
  @spec restart_projections() :: :ok
  def restart_projections do
    require Logger
    Logger.info("API: Attempting to restart EventTypeProjectionManager")

    case RegulateGreenhouse.Projections.EventTypeProjectionManager.status() do
      projections when is_list(projections) ->
        Logger.info("API: Event type projections status: #{inspect(projections)}")

        # Restart any failed projections
        failed_projections =
          Enum.filter(projections, fn {_, status} -> status == :not_running end)

        if length(failed_projections) > 0 do
          Logger.info("API: Restarting #{length(failed_projections)} failed projections")

          Enum.each(failed_projections, fn {event_type, _} ->
            case RegulateGreenhouse.Projections.EventTypeProjectionManager.restart_projection(
                   event_type
                 ) do
              :ok ->
                Logger.info("API: Restarted #{event_type} projection")

              error ->
                Logger.error("API: Failed to restart #{event_type} projection: #{inspect(error)}")
            end
          end)
        else
          Logger.info("API: All event type projections are running")
        end

        :ok

      error ->
        Logger.error("API: Failed to get projection status: #{inspect(error)}")
        error
    end
  end
end
