defmodule RegulateGreenhouse.API do
  @moduledoc """
  Public API for the RegulateGreenhouse Commanded application.
  
  This module provides functions to dispatch commands and query
  the greenhouse regulation domain.
  """

  alias RegulateGreenhouse.CommandedApp
  alias RegulateGreenhouse.Commands.{
    CreateGreenhouse,
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
  def create_greenhouse(greenhouse_id, name, location, target_temperature \\ nil, target_humidity \\ nil) do
    require Logger
    
    command = %CreateGreenhouse{
      greenhouse_id: greenhouse_id,
      name: name,
      location: location,
      target_temperature: target_temperature,
      target_humidity: target_humidity
    }

    case CommandedApp.dispatch_command(command) do
      :ok -> :ok
      error ->
        Logger.error("API: Failed to dispatch CreateGreenhouse for #{greenhouse_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Initializes a greenhouse with sensor readings.
  """
  @spec initialize_greenhouse(String.t(), float(), float(), float()) :: :ok | {:error, term()}
  def initialize_greenhouse(greenhouse_id, temperature, humidity, light) do
    require Logger
    Logger.info("API: Initializing greenhouse #{greenhouse_id} - ONLY CREATING, measurements disabled for debugging")
    
    # First create the greenhouse
    case create_greenhouse(greenhouse_id, greenhouse_id, "Unknown") do
      :ok -> 
        Logger.info("API: Greenhouse #{greenhouse_id} created successfully (measurements disabled)")
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
      error -> error
    end
  end

  @doc """
  Sets the target temperature for a greenhouse.
  """
  @spec set_temperature(String.t(), float(), String.t() | nil) :: :ok | {:error, term()}
  def set_temperature(greenhouse_id, target_temperature, set_by \\ nil) do
    require Logger
    Logger.info("API: Setting temperature for #{greenhouse_id} to #{target_temperature}°C (set_by: #{set_by})")
    
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
    Logger.info("API: Setting humidity for #{greenhouse_id} to #{target_humidity}% (set_by: #{set_by})")
    
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
        Logger.error("API: Failed to record temperature measurement for #{greenhouse_id}: #{inspect(error)}")
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
        Logger.error("API: Failed to record humidity measurement for #{greenhouse_id}: #{inspect(error)}")
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
        Logger.error("API: Failed to record light measurement for #{greenhouse_id}: #{inspect(error)}")
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
        {:ok, %{
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
  def get_greenhouse_events(_greenhouse_id, _limit) do
    # For now, return empty list. In a real app, you might
    # query the event store directly or maintain events in a projection
    []
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
        failed_projections = Enum.filter(projections, fn {_, status} -> status == :not_running end)
        
        if length(failed_projections) > 0 do
          Logger.info("API: Restarting #{length(failed_projections)} failed projections")
          
          Enum.each(failed_projections, fn {event_type, _} ->
            case RegulateGreenhouse.Projections.EventTypeProjectionManager.restart_projection(event_type) do
              :ok -> Logger.info("API: Restarted #{event_type} projection")
              error -> Logger.error("API: Failed to restart #{event_type} projection: #{inspect(error)}")
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
