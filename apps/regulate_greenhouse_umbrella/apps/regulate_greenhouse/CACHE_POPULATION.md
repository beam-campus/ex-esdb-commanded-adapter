# Cache Population System

The RegulateGreenhouse application includes a robust cache population system that automatically rebuilds the greenhouse read model cache from ExESDB event streams during application startup.

## Overview

When the application restarts, the in-memory cache (powered by Cachex) is empty, but the events are still persisted in ExESDB. The cache population system automatically:

1. **Waits for ExESDB connectivity** - Ensures the event store is available before attempting to read streams
2. **Checks cache status** - Determines if population is needed by comparing cache size to stream count
3. **Rebuilds cache** - Replays events through existing event handlers to reconstruct read models
4. **Retries on failure** - Uses exponential backoff to handle temporary connectivity issues
5. **Provides monitoring** - Logs detailed information about the population process

## Configuration

### Enable/Disable Cache Population

Cache population is controlled via application configuration:

```elixir
# Enable automatic cache population on startup (default: true)
config :regulate_greenhouse, :populate_cache_on_startup, true

# Disable cache population
config :regulate_greenhouse, :populate_cache_on_startup, false
```

### Environment Variables

You can also control cache population via environment variables:

```bash
# Disable cache population for testing
export POPULATE_CACHE_ON_STARTUP=false

# Re-enable for normal operation
export POPULATE_CACHE_ON_STARTUP=true
```

## API Functions

### Check Population Status

```elixir
# Get the current status of cache population
{:ok, status} = RegulateGreenhouse.API.get_cache_population_status()

# Example response:
%{
  status: :completed,           # :waiting, :populating, :completed, :failed, :retrying
  retry_count: 0,
  last_error: nil,
  population_stats: %{
    duration_ms: 1245,
    events_processed: 157,
    greenhouses_created: 12,
    cache_size: 12
  },
  started_at: ~U[2024-01-01 10:00:00Z],
  enabled: true
}
```

### Manual Cache Population

```elixir
# Manually trigger cache population (useful for recovery)
:ok = RegulateGreenhouse.API.populate_cache()

# Check status after manual trigger
{:ok, status} = RegulateGreenhouse.API.get_cache_population_status()
```

### Direct Cache Rebuild

```elixir
# Low-level cache rebuild (bypasses the population service)
{:ok, stats} = RegulateGreenhouse.API.rebuild_cache()

# Example stats:
%{
  duration_ms: 1245,
  events_processed: 157,
  events_failed: 0,
  greenhouses_created: 12,
  streams_processed: 12,
  cache_size: 12,
  errors: []
}
```

### Partial Cache Rebuild

```elixir
# Rebuild cache for specific streams only
stream_ids = ["regulate_greenhouse_greenhouse1", "regulate_greenhouse_greenhouse2"]
{:ok, stats} = RegulateGreenhouse.CacheRebuildService.rebuild_cache_for_streams(stream_ids)
```

## How It Works

### 1. Startup Sequence

```
Application Start → CachePopulationService → Wait 2s → Check ExESDB → Population Logic
```

### 2. ExESDB Connectivity Check

The service waits up to 30 seconds for ExESDB to become available, checking every second:

```elixir
# Checks if API.get_streams(:reg_gh) succeeds
case ExESDBGater.API.get_streams(:reg_gh) do
  {:ok, streams} -> :ok  # ExESDB is ready
  {:error, _} -> retry   # Keep trying
end
```

### 3. Cache Status Assessment

```elixir
cache_size = RegulateGreenhouse.CacheService.count_greenhouses()
{:ok, streams} = ExESDBGater.API.get_streams(:reg_gh)
stream_count = length(streams)

# If cache size is roughly similar to stream count, skip population
if cache_size >= stream_count * 0.8 do
  {:no_population_needed, cache_size}
else
  {:needs_population, stream_count}
end
```

### 4. Event Replay Process

The cache rebuild process:

1. **Reads all streams** from ExESDB using `API.get_streams/1`
2. **Processes streams in batches** of 100 events to avoid memory issues
3. **Replays events** through existing event handlers:
   - `GreenhouseEventHandler` for `initialized:v1` events
   - `TemperatureEventHandler` for temperature events
   - `HumidityEventHandler` for humidity events
   - `LightEventHandler` for light events
4. **Updates the cache** using the same logic as real-time event processing
5. **Returns statistics** about the rebuild process

### 5. Error Handling and Retries

- **Exponential backoff**: Retries with increasing delays (1s, 2s, 4s, 8s, ...)
- **Maximum retries**: Up to 10 attempts before giving up
- **Jitter**: Adds randomness to retry delays to avoid thundering herd
- **Detailed logging**: Comprehensive logs for troubleshooting

## Monitoring and Troubleshooting

### Log Messages

The cache population service provides detailed logging:

```
[info] CachePopulationService: Starting cache population service
[info] CachePopulationService: ExESDB connectivity confirmed on attempt 1
[info] CachePopulationService: Cache needs population (12 streams found)
[info] CacheRebuildService: Found 12 streams to rebuild
[info] CacheRebuildService: Processing 157 events for stream regulate_greenhouse_greenhouse1
[info] CachePopulationService: Cache population completed successfully
[info] CachePopulationService: Population stats: %{...}
```

### Common Issues

**Issue**: Cache population fails with connectivity errors
**Solution**: Ensure ExESDB and ExESDB Gater are running and accessible

**Issue**: Cache population takes too long
**Solution**: Check the number of streams and events - large datasets take longer

**Issue**: Cache is partially populated
**Solution**: Check for errors in event processing logs, some events may have failed

**Issue**: Cache population keeps retrying
**Solution**: Check ExESDB cluster health and network connectivity

### Performance Considerations

- **Memory usage**: Large event histories consume more memory during rebuild
- **Startup time**: Cache population adds to application startup time
- **Network traffic**: Reading events generates network traffic to ExESDB
- **CPU usage**: Event processing uses CPU cycles during startup

### Testing

For testing environments, you may want to disable cache population:

```elixir
# In config/test.exs
config :regulate_greenhouse, :populate_cache_on_startup, false
```

Or control it per test:

```elixir
# In test setup
Application.put_env(:regulate_greenhouse, :populate_cache_on_startup, false)
```

## Integration with Your Application

The cache population system integrates seamlessly with your existing event sourcing infrastructure:

1. **Uses existing event handlers** - No duplication of business logic
2. **Works with existing cache** - Uses the same Cachex cache as real-time processing
3. **Respects user preferences** - Follows your libcluster-based topology preference
4. **Provides observability** - Rich logging and status reporting
5. **Handles errors gracefully** - Comprehensive error handling and recovery

The system ensures your application can quickly recover from restarts while maintaining data consistency through event sourcing principles.

<citations>
<document>
<document_type>RULE</document_type>
<document_id>Eo9EMcgHQ2u2Ek5kXxYBHh</document_id>
</document>
</citations>
