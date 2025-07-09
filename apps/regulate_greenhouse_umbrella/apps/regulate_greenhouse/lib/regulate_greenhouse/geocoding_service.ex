defmodule RegulateGreenhouse.GeocodingService do
  @moduledoc """
  Geocoding service to convert city names to coordinates using Open-Meteo Geocoding API.
  
  Open-Meteo provides free geocoding without requiring an API key.
  """
  
  require Logger
  
  @base_url "https://geocoding-api.open-meteo.com/v1"
  
  @doc """
  Converts a city name and country code to coordinates.
  
  ## Parameters
  - `city`: City name (string)
  - `country_code`: ISO 3166 country code (string)
  - `api_key`: Not used (Open-Meteo is free and doesn't require API key)
  
  ## Returns
  - `{:ok, {lat, lon}}` on success
  - `{:error, reason}` on failure
  """
  @spec geocode_city(String.t(), String.t(), String.t()) :: {:ok, {float(), float()}} | {:error, term()}
  def geocode_city(city, country_code, _api_key) do
    url = "#{@base_url}/search"
    
    params = %{
      name: city,
      count: 1,
      language: "en",
      format: "json"
    }
    
    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"
    
    Logger.info("GeocodingService: Geocoding #{city}, #{country_code}")
    
    case Finch.build(:get, full_url) |> Finch.request(RegulateGreenhouse.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => []}} ->
            Logger.warning("GeocodingService: No results found for #{city}, #{country_code}")
            {:error, :not_found}
          
          {:ok, %{"results" => [result | _]}} ->
            lat = result["latitude"]
            lon = result["longitude"]
            result_country = result["country_code"]
            
            # Filter by country code if provided
            if result_country && !country_matches?(result_country, country_code) do
              Logger.warning("GeocodingService: Country mismatch for #{city}: expected #{country_code}, got #{result_country}")
              {:error, :country_mismatch}
            else
              if lat && lon do
                Logger.info("GeocodingService: Successfully geocoded #{city}, #{country_code} to #{lat}, #{lon}")
                {:ok, {lat, lon}}
              else
                Logger.error("GeocodingService: Invalid coordinate data in response")
                {:error, :invalid_response}
              end
            end
          
          {:error, reason} ->
            Logger.error("GeocodingService: Failed to parse JSON response: #{inspect(reason)}")
            {:error, {:json_parse_error, reason}}
        end
      
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("GeocodingService: API request failed with status #{status}: #{body}")
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        Logger.error("GeocodingService: HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end
  
  @doc """
  Converts coordinates back to a location string for storage.
  
  ## Parameters
  - `lat`: Latitude (float)
  - `lon`: Longitude (float)
  
  ## Returns
  - Location string in "lat,lon" format
  """
  @spec coordinates_to_location_string(float(), float()) :: String.t()
  def coordinates_to_location_string(lat, lon) do
    "#{lat},#{lon}"
  end
  
  @doc """
  Get a list of major cities for a given country code.
  This is a simple static list - in a real application, you might want to use a more comprehensive database.
  """
  @spec get_major_cities(String.t()) :: [String.t()]
  def get_major_cities(country_code) do
    case String.upcase(country_code) do
      "US" -> ["New York", "Los Angeles", "Chicago", "Houston", "Phoenix", "Philadelphia", "San Antonio", "San Diego", "Dallas", "San Jose"]
      "CA" -> ["Toronto", "Montreal", "Vancouver", "Calgary", "Edmonton", "Ottawa", "Winnipeg", "Quebec City", "Hamilton", "London"]
      "GB" -> ["London", "Birmingham", "Manchester", "Liverpool", "Leeds", "Sheffield", "Bristol", "Newcastle", "Leicester", "Nottingham"]
      "DE" -> ["Berlin", "Hamburg", "Munich", "Cologne", "Frankfurt", "Stuttgart", "Düsseldorf", "Dortmund", "Essen", "Bremen"]
      "FR" -> ["Paris", "Marseille", "Lyon", "Toulouse", "Nice", "Nantes", "Strasbourg", "Montpellier", "Bordeaux", "Lille"]
      "IT" -> ["Rome", "Milan", "Naples", "Turin", "Palermo", "Genoa", "Bologna", "Florence", "Bari", "Catania"]
      "ES" -> ["Madrid", "Barcelona", "Valencia", "Seville", "Zaragoza", "Málaga", "Murcia", "Palma", "Las Palmas", "Bilbao"]
      "NL" -> ["Amsterdam", "Rotterdam", "The Hague", "Utrecht", "Eindhoven", "Tilburg", "Groningen", "Almere", "Breda", "Nijmegen"]
      "AU" -> ["Sydney", "Melbourne", "Brisbane", "Perth", "Adelaide", "Gold Coast", "Newcastle", "Canberra", "Sunshine Coast", "Wollongong"]
      "JP" -> ["Tokyo", "Osaka", "Yokohama", "Nagoya", "Sapporo", "Fukuoka", "Kobe", "Kyoto", "Kawasaki", "Saitama"]
      "CN" -> ["Beijing", "Shanghai", "Guangzhou", "Shenzhen", "Chengdu", "Nanjing", "Hangzhou", "Xi'an", "Wuhan", "Tianjin"]
      "BR" -> ["São Paulo", "Rio de Janeiro", "Brasília", "Salvador", "Fortaleza", "Belo Horizonte", "Manaus", "Curitiba", "Recife", "Porto Alegre"]
      "MX" -> ["Mexico City", "Guadalajara", "Monterrey", "Puebla", "Tijuana", "León", "Juárez", "Torreón", "Querétaro", "San Luis Potosí"]
      "IN" -> ["Mumbai", "Delhi", "Bangalore", "Hyderabad", "Chennai", "Kolkata", "Pune", "Ahmedabad", "Jaipur", "Surat"]
      "ZA" -> ["Cape Town", "Johannesburg", "Durban", "Pretoria", "Port Elizabeth", "Bloemfontein", "East London", "Nelspruit", "Kimberley", "Polokwane"]
      _ -> []
    end
  end
  
  # Private helper functions
  
  defp country_matches?(result_country_code, expected_country) do
    result_code = String.upcase(result_country_code)
    expected_upper = String.upcase(expected_country)
    
    # Direct code match
    if result_code == expected_upper do
      true
    else
      # Check if expected_country is a country name that maps to result_code
      case country_name_to_code(expected_upper) do
        ^result_code -> true
        _ -> false
      end
    end
  end
  
  defp country_name_to_code(country_name) do
    case String.upcase(country_name) do
      "BELGIUM" -> "BE"
      "GERMANY" -> "DE"
      "FRANCE" -> "FR"
      "ITALY" -> "IT"
      "SPAIN" -> "ES"
      "NETHERLANDS" -> "NL"
      "UNITED KINGDOM" -> "GB"
      "UNITED STATES" -> "US"
      "CANADA" -> "CA"
      "AUSTRALIA" -> "AU"
      "JAPAN" -> "JP"
      "CHINA" -> "CN"
      "BRAZIL" -> "BR"
      "MEXICO" -> "MX"
      "INDIA" -> "IN"
      "SOUTH AFRICA" -> "ZA"
      "DENMARK" -> "DK"
      "SWEDEN" -> "SE"
      "NORWAY" -> "NO"
      "FINLAND" -> "FI"
      "POLAND" -> "PL"
      "AUSTRIA" -> "AT"
      "SWITZERLAND" -> "CH"
      "PORTUGAL" -> "PT"
      "GREECE" -> "GR"
      "TURKEY" -> "TR"
      "RUSSIA" -> "RU"
      "CZECH REPUBLIC" -> "CZ"
      "CZECHIA" -> "CZ"
      "HUNGARY" -> "HU"
      "ROMANIA" -> "RO"
      "IRELAND" -> "IE"
      "UKRAINE" -> "UA"
      "SOUTH KOREA" -> "KR"
      "NEW ZEALAND" -> "NZ"
      "ARGENTINA" -> "AR"
      "CHILE" -> "CL"
      "ISRAEL" -> "IL"
      "SAUDI ARABIA" -> "SA"
      "UNITED ARAB EMIRATES" -> "AE"
      "EGYPT" -> "EG"
      "MOROCCO" -> "MA"
      "ALGERIA" -> "DZ"
      "TUNISIA" -> "TN"
      "NIGERIA" -> "NG"
      "KENYA" -> "KE"
      "ETHIOPIA" -> "ET"
      "GHANA" -> "GH"
      "UGANDA" -> "UG"
      "TANZANIA" -> "TZ"
      "ZIMBABWE" -> "ZW"
      "ZAMBIA" -> "ZM"
      "BOTSWANA" -> "BW"
      "NAMIBIA" -> "NA"
      "ANGOLA" -> "AO"
      "MOZAMBIQUE" -> "MZ"
      "MADAGASCAR" -> "MG"
      "MAURITIUS" -> "MU"
      "SEYCHELLES" -> "SC"
      "CUBA" -> "CU"
      "JAMAICA" -> "JM"
      "DOMINICAN REPUBLIC" -> "DO"
      "PUERTO RICO" -> "PR"
      "BAHAMAS" -> "BS"
      "BARBADOS" -> "BB"
      "HAITI" -> "HT"
      "TRINIDAD AND TOBAGO" -> "TT"
      "GREENLAND" -> "GL"
      "ICELAND" -> "IS"
      "CYPRUS" -> "CY"
      "MALTA" -> "MT"
      "LUXEMBOURG" -> "LU"
      "PAKISTAN" -> "PK"
      "BANGLADESH" -> "BD"
      "SRI LANKA" -> "LK"
      "NEPAL" -> "NP"
      "BHUTAN" -> "BT"
      "MALDIVES" -> "MV"
      "MYANMAR" -> "MM"
      "CAMBODIA" -> "KH"
      "LAOS" -> "LA"
      "MONGOLIA" -> "MN"
      "TAIWAN" -> "TW"
      "HONG KONG" -> "HK"
      "THAILAND" -> "TH"
      "VIETNAM" -> "VN"
      "MALAYSIA" -> "MY"
      "SINGAPORE" -> "SG"
      "INDONESIA" -> "ID"
      "PHILIPPINES" -> "PH"
      "BOLIVIA" -> "BO"
      "PERU" -> "PE"
      "ECUADOR" -> "EC"
      "COLOMBIA" -> "CO"
      "VENEZUELA" -> "VE"
      "URUGUAY" -> "UY"
      "PARAGUAY" -> "PY"
      # Return the original if not found (might already be a code)
      _ -> country_name
    end
  end
end
