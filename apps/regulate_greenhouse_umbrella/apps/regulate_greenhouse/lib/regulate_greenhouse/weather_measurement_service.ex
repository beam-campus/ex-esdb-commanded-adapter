defmodule RegulateGreenhouse.WeatherMeasurementService do
  @moduledoc """
  GenServer that periodically fetches weather data and updates greenhouse measurements
  based on real-world weather conditions.
  """
  
  use GenServer
  require Logger
  
  alias RegulateGreenhouse.{API, WeatherService}
  
  @measurement_interval 60_000  # 1 minute
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("WeatherMeasurementService: Starting with Open-Meteo API (no key required)")
    timer = schedule_next_measurement()
    {:ok, %{enabled: true, timer: timer}}
  end
  
  def handle_info(:measure_all_greenhouses, state) do
    if state.enabled do
      measure_all_greenhouses()
      timer = schedule_next_measurement()
      {:noreply, %{state | timer: timer}}
    else
      {:noreply, state}
    end
  end
  
  def handle_info({:measure_greenhouse, greenhouse_id, coordinates}, state) do
    if state.enabled do
      measure_single_greenhouse(greenhouse_id, coordinates)
    end
    {:noreply, state}
  end
  
  def handle_call({:measure_greenhouse_now, greenhouse_id, coordinates}, _from, state) do
    result = if state.enabled do
      measure_single_greenhouse(greenhouse_id, coordinates)
    else
      {:error, :service_disabled}
    end
    
    {:reply, result, state}
  end
  
  def handle_call(:get_status, _from, state) do
    status = %{
      enabled: state.enabled,
      api_provider: "Open-Meteo",
      next_measurement: get_next_measurement_time(state.timer)
    }
    {:reply, status, state}
  end
  
  # Public API
  
  @doc """
  Manually trigger a measurement for a specific greenhouse.
  """
  def measure_greenhouse_now(greenhouse_id, lat, lon) do
    GenServer.call(__MODULE__, {:measure_greenhouse_now, greenhouse_id, {lat, lon}})
  end
  
  @doc """
  Get the current status of the weather measurement service.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Schedule a delayed measurement for a specific greenhouse.
  """
  def schedule_greenhouse_measurement(greenhouse_id, lat, lon, delay_ms \\ 0) do
    Process.send_after(__MODULE__, {:measure_greenhouse, greenhouse_id, {lat, lon}}, delay_ms)
  end
  
  # Private functions
  
  defp schedule_next_measurement do
    Process.send_after(self(), :measure_all_greenhouses, @measurement_interval)
  end
  
  defp get_next_measurement_time(timer) do
    if timer do
      remaining_ms = Process.read_timer(timer)
      if remaining_ms do
        DateTime.add(DateTime.utc_now(), remaining_ms, :millisecond)
      else
        nil
      end
    else
      nil
    end
  end
  
  defp measure_all_greenhouses do
    Logger.info("WeatherMeasurementService: Starting measurement cycle for all greenhouses")
    
    greenhouses = get_greenhouses_with_coordinates()
    
    Logger.info("WeatherMeasurementService: Found #{length(greenhouses)} greenhouses with coordinates")
    
    # Stagger the measurements to avoid overwhelming the API
    greenhouses
    |> Enum.with_index()
    |> Enum.each(fn {{greenhouse_id, coordinates}, index} ->
      delay = index * 1000  # 1 second delay between each measurement (Open-Meteo is more generous)
      schedule_greenhouse_measurement(greenhouse_id, elem(coordinates, 0), elem(coordinates, 1), delay)
    end)
  end
  
  defp measure_single_greenhouse(greenhouse_id, {lat, lon}) do
    Logger.info("WeatherMeasurementService: Measuring greenhouse #{greenhouse_id} at lat=#{lat}, lon=#{lon}")
    
    case WeatherService.get_current_weather(lat, lon, nil) do
      {:ok, weather_data} ->
        greenhouse_conditions = WeatherService.weather_to_greenhouse_conditions(weather_data)
        
        Logger.info("WeatherMeasurementService: Weather conditions for #{greenhouse_id}: #{inspect(greenhouse_conditions)}")
        
        # Send measurements to the greenhouse
        results = [
          API.measure_temperature(greenhouse_id, greenhouse_conditions.temperature),
          API.measure_humidity(greenhouse_id, greenhouse_conditions.humidity),
          API.measure_light(greenhouse_id, greenhouse_conditions.light)
        ]
        
        case Enum.all?(results, &(&1 == :ok)) do
          true ->
            Logger.info("WeatherMeasurementService: Successfully updated measurements for #{greenhouse_id}")
            {:ok, greenhouse_conditions}
          
          false ->
            Logger.error("WeatherMeasurementService: Some measurements failed for #{greenhouse_id}: #{inspect(results)}")
            {:error, :measurement_failed}
        end
      
      {:error, reason} ->
        Logger.error("WeatherMeasurementService: Failed to fetch weather data for #{greenhouse_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp get_greenhouses_with_coordinates do
    # Get all greenhouses and filter those with valid coordinates
    API.list_greenhouses()
    |> Enum.map(fn greenhouse_id ->
      case get_greenhouse_coordinates(greenhouse_id) do
        {:ok, {lat, lon}} -> {greenhouse_id, {lat, lon}}
        {:error, _} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end
  
  defp get_greenhouse_coordinates(greenhouse_id) do
    case API.get_greenhouse_state(greenhouse_id) do
      {:ok, state} ->
        # The state comes from the cache service, let's try to get location from the read model
        case RegulateGreenhouse.CacheService.get_greenhouse(greenhouse_id) do
          {:ok, greenhouse} when not is_nil(greenhouse) ->
            parse_location_coordinates(greenhouse.location)
          
          _ ->
            Logger.warning("WeatherMeasurementService: Could not get greenhouse #{greenhouse_id} from cache")
            {:error, :not_found}
        end
      
      {:error, reason} ->
        Logger.warning("WeatherMeasurementService: Could not get state for #{greenhouse_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp parse_location_coordinates(location) when is_binary(location) do
    # Try to parse location as "lat,lon" format
    case String.split(location, ",") do
      [lat_str, lon_str] ->
        with {lat, ""} <- Float.parse(String.trim(lat_str)),
             {lon, ""} <- Float.parse(String.trim(lon_str)) do
          {:ok, {lat, lon}}
        else
          _ -> {:error, :invalid_coordinates}
        end
      
      _ ->
        {:error, :invalid_format}
    end
  end
  
  defp parse_location_coordinates(_), do: {:error, :invalid_location}
end
