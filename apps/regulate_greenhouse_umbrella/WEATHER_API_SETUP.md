# Open-Meteo API Integration Setup

## Overview
This greenhouse management system integrates with Open-Meteo API to provide real-time weather data for automated greenhouse environmental control.

**Open-Meteo is completely free and requires no API key!**

## Features
- **Real-time Weather Data**: Fetch current weather conditions for greenhouse locations
- **Geocoding**: Convert city names to coordinates automatically
- **Automated Measurements**: Correlate outdoor weather with greenhouse conditions
- **Country/City Selection**: User-friendly location selection interface
- **No API Key Required**: Open-Meteo is free and open-source

## API Setup

### No Setup Required!
Unlike other weather services, Open-Meteo requires no API key registration. Simply start the application:

```bash
mix phx.server
```

## Features Enabled

### Weather-Based Measurements
- Automatic periodic updates every 60 seconds
- Realistic temperature, humidity, and light values based on:
  - Outdoor temperature with greenhouse effect
  - Local humidity with greenhouse modifications
  - Cloud cover and weather conditions affecting light levels

### Greenhouse Initialization
- Select country from dropdown
- Enter city name
- Automatic geocoding to coordinates
- Weather data fetching for the location

### Fallback Behavior
- If geocoding fails: Shows error message
- Service unavailable: Falls back to manual measurements
- No API key management required

## Weather Data Correlation

### Temperature
- **Cold weather** (< 0°C): +8°C greenhouse effect
- **Cool weather** (0-15°C): +5°C greenhouse effect
- **Mild weather** (15-25°C): +3°C greenhouse effect
- **Warm weather** (> 25°C): +1°C greenhouse effect

### Humidity
- **Dry conditions** (< 30%): +25% greenhouse increase
- **Moderate humidity** (30-60%): +15% greenhouse increase
- **High humidity** (> 60%): +10% greenhouse increase

### Light Levels
- Based on weather conditions and cloud cover
- Adjusted for greenhouse light transmission (typically 65%)
- Accounts for seasonal and daily variations

## API Endpoints Used

### Current Weather
- **URL**: `https://api.open-meteo.com/v1/current`
- **Usage**: Get current weather conditions for greenhouse location
- **Parameters**: latitude, longitude, current weather variables

### Geocoding
- **URL**: `https://geocoding-api.open-meteo.com/v1/search`
- **Usage**: Convert city names to coordinates
- **Parameters**: name, count, language, format

### UV Index
- **URL**: `https://api.open-meteo.com/v1/current`
- **Usage**: Get UV index for accurate light level calculations
- **Parameters**: latitude, longitude, current=uv_index

## Rate Limits
- **Free tier**: 10,000 calls/day (very generous)
- **Measurement service**: Staggers requests by 1 second intervals
- **Geocoding**: Only called during greenhouse initialization
- **No API key required**: Open-source and free

## Testing
1. Start the application (no API key needed!)
2. Initialize a new greenhouse with country/city selection
3. Monitor logs for weather data fetching
4. Check that greenhouse readings update with realistic values
5. Verify Open-Meteo API responses in logs

## Troubleshooting

### No Weather Updates
- Verify internet connectivity
- Check application logs for API errors
- Ensure Open-Meteo service is accessible

### Geocoding Failures
- Ensure city name is spelled correctly
- Try major cities in the selected country
- Check Open-Meteo geocoding service status

### Rate Limits (Unlikely with Open-Meteo)
- Open-Meteo has generous rate limits (10,000 calls/day)
- Measurement service already staggers requests
- Monitor logs for any rate limit messages
