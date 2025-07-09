defmodule RegulateGreenhouse.WeatherService do
  @moduledoc """
  Weather service for integrating with Open-Meteo API.
  
  Provides functions to fetch current weather data and correlate it with
  greenhouse environmental conditions.
  
  Open-Meteo is a free, open-source weather API that doesn't require an API key.
  """
  
  require Logger
  
  @base_url "https://api.open-meteo.com/v1"
  
  @doc """
  Fetches current weather data for a given location.
  
  ## Parameters
  - `lat`: Latitude (float)
  - `lon`: Longitude (float)
  - `api_key`: Not used (Open-Meteo is free and doesn't require API key)
  
  ## Returns
  - `{:ok, weather_data}` on success
  - `{:error, reason}` on failure
  """
  @spec get_current_weather(float(), float(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_current_weather(lat, lon, _api_key) do
    url = "#{@base_url}/forecast"
    
    params = %{
      latitude: lat,
      longitude: lon,
      current: "temperature_2m,relative_humidity_2m,weather_code,cloud_cover,wind_speed_10m",
      timezone: "auto"
    }
    
    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"
    
    Logger.info("WeatherService: Fetching weather data for lat=#{lat}, lon=#{lon}")
    
    case Finch.build(:get, full_url) |> Finch.request(RegulateGreenhouse.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.info("WeatherService: Successfully fetched weather data")
            {:ok, normalize_weather_data(data)}
          
          {:error, reason} ->
            Logger.error("WeatherService: Failed to parse JSON response: #{inspect(reason)}")
            {:error, {:json_parse_error, reason}}
        end
      
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("WeatherService: API request failed with status #{status}: #{body}")
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        Logger.error("WeatherService: HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end
  
  @doc """
  Fetches UV index data for a given location.
  
  ## Parameters
  - `lat`: Latitude (float)
  - `lon`: Longitude (float)
  - `api_key`: Not used (Open-Meteo is free and doesn't require API key)
  
  ## Returns
  - `{:ok, uv_data}` on success
  - `{:error, reason}` on failure
  """
  @spec get_uv_index(float(), float(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_uv_index(lat, lon, _api_key) do
    url = "#{@base_url}/forecast"
    
    params = %{
      latitude: lat,
      longitude: lon,
      current: "uv_index",
      timezone: "auto"
    }
    
    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"
    
    Logger.info("WeatherService: Fetching UV index for lat=#{lat}, lon=#{lon}")
    
    case Finch.build(:get, full_url) |> Finch.request(RegulateGreenhouse.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.info("WeatherService: Successfully fetched UV index data")
            uv_value = get_in(data, ["current", "uv_index"]) || 0
            {:ok, %{"value" => uv_value}}
          
          {:error, reason} ->
            Logger.error("WeatherService: Failed to parse UV JSON response: #{inspect(reason)}")
            {:error, {:json_parse_error, reason}}
        end
      
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("WeatherService: UV API request failed with status #{status}: #{body}")
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        Logger.error("WeatherService: UV HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end
  
  @doc """
  Converts outdoor weather conditions to estimated greenhouse conditions.
  
  Greenhouses typically have:
  - Higher temperature (due to greenhouse effect)
  - Higher humidity (controlled environment)
  - Reduced light (filtered through glass/plastic)
  """
  @spec weather_to_greenhouse_conditions(map()) :: map()
  def weather_to_greenhouse_conditions(weather_data) do
    outdoor_temp = weather_data.temperature
    outdoor_humidity = weather_data.humidity
    
    # Estimate greenhouse conditions based on outdoor weather
    greenhouse_temp = outdoor_temp + greenhouse_temperature_offset(outdoor_temp)
    greenhouse_humidity = min(outdoor_humidity + greenhouse_humidity_offset(outdoor_humidity), 100)
    greenhouse_light = estimate_greenhouse_light(weather_data)
    
    %{
      temperature: Float.round(greenhouse_temp, 1),
      humidity: Float.round(greenhouse_humidity, 1),
      light: Float.round(greenhouse_light, 1)
    }
  end
  
  # Private functions
  
  defp normalize_weather_data(raw_data) do
    current = get_in(raw_data, ["current"]) || %{}
    
    %{
      temperature: get_in(current, ["temperature_2m"]) || 0.0,
      humidity: get_in(current, ["relative_humidity_2m"]) || 0.0,
      pressure: 1013.25,  # Open-Meteo doesn't provide pressure in current endpoint
      weather_condition: weather_code_to_condition(get_in(current, ["weather_code"]) || 0),
      clouds: get_in(current, ["cloud_cover"]) || 0,
      wind_speed: get_in(current, ["wind_speed_10m"]) || 0.0,
      city: "Unknown",  # Open-Meteo doesn't provide city name in weather response
      country: "Unknown"  # Open-Meteo doesn't provide country in weather response
    }
  end
  
  defp weather_code_to_condition(weather_code) do
    case weather_code do
      0 -> "Clear"
      1 -> "Clear"
      2 -> "Clouds"
      3 -> "Clouds"
      45 -> "Fog"
      48 -> "Fog"
      51 -> "Drizzle"
      53 -> "Drizzle"
      55 -> "Drizzle"
      56 -> "Drizzle"
      57 -> "Drizzle"
      61 -> "Rain"
      63 -> "Rain"
      65 -> "Rain"
      66 -> "Rain"
      67 -> "Rain"
      71 -> "Snow"
      73 -> "Snow"
      75 -> "Snow"
      77 -> "Snow"
      80 -> "Rain"
      81 -> "Rain"
      82 -> "Rain"
      85 -> "Snow"
      86 -> "Snow"
      95 -> "Thunderstorm"
      96 -> "Thunderstorm"
      99 -> "Thunderstorm"
      _ -> "Unknown"
    end
  end
  
  defp greenhouse_temperature_offset(outdoor_temp) do
    cond do
      outdoor_temp < 0 -> 8.0    # Cold weather: significant greenhouse effect
      outdoor_temp < 15 -> 5.0   # Cool weather: moderate greenhouse effect
      outdoor_temp < 25 -> 3.0   # Mild weather: small greenhouse effect
      true -> 1.0                # Warm weather: minimal greenhouse effect
    end
  end
  
  defp greenhouse_humidity_offset(outdoor_humidity) do
    cond do
      outdoor_humidity < 30 -> 25.0  # Dry air: greenhouse adds moisture
      outdoor_humidity < 60 -> 15.0  # Moderate humidity: some increase
      true -> 10.0                   # Already humid: small increase
    end
  end
  
  defp estimate_greenhouse_light(weather_data) do
    cloud_cover = weather_data.clouds
    base_light = case weather_data.weather_condition do
      "Clear" -> 85.0
      "Clouds" -> 60.0
      "Rain" -> 40.0
      "Drizzle" -> 45.0
      "Thunderstorm" -> 25.0
      "Snow" -> 35.0
      "Mist" -> 50.0
      "Fog" -> 30.0
      _ -> 55.0
    end
    
    # Adjust for cloud cover and greenhouse light transmission (typically 60-70%)
    cloud_factor = 1.0 - (cloud_cover / 100.0 * 0.6)
    greenhouse_transmission = 0.65
    
    base_light * cloud_factor * greenhouse_transmission
  end
end
