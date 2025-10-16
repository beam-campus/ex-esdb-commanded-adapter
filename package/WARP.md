# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is the **ExESDB Commanded Adapter** - an Elixir library that provides a bridge between the [Commanded](https://github.com/commanded/commanded) CQRS/ES framework and [ExESDB](https://github.com/beam-campus/ex-esdb) (a distributed event store built on Erlang/OTP). The adapter implements the `Commanded.EventStore.Adapter` behaviour to enable Commanded applications to use ExESDB as their event store backend.

## Development Commands

### Core Mix Commands

```bash
# Get dependencies
mix deps.get

# Compile the project
mix compile

# Run all tests (excludes integration tests by default)
mix test

# Run tests with coverage
mix test --cover

# Run with detailed output
mix test --trace

# Generate documentation
mix docs

# Type checking with Dialyzer
mix dialyzer
```

### Test Execution

```bash
# Run unit tests only (excludes integration tests)
mix test --exclude integration

# Run integration tests only (requires ExESDB v0.4.1)
mix test --only integration

# Run integration tests with verbose output
mix test --only integration --trace

# Run specific test file
mix test test/commanded/adapter_test.exs

# Run specific test with line number
mix test test/integration/adapter_integration_test.exs:53

# Run integration tests with environment setup
INTEGRATION_TEST=true mix test --only integration
```

### Development Tools

```bash
# Watch tests during development
mix test.watch

# Code formatting
mix format

# Linting with Credo
mix credo

# Check for unused dependencies
mix deps.unlock --check-unused
```

### Documentation and Release

```bash
# Build and serve docs locally
mix docs && open doc/index.html

# Create release
mix release
```

## Architecture Overview

### Core Components

The adapter is built around several key components that work together to bridge Commanded and ExESDB:

#### 1. **Adapter Module** (`lib/commanded/adapter.ex`)
- **Primary Interface**: Implements the `Commanded.EventStore.Adapter` behaviour
- **Event Management**: Handles `append_to_stream/5`, `stream_forward/4`, and snapshot operations
- **Subscription Management**: Manages both transient and persistent subscriptions
- **Store Integration**: Delegates to ExESDBGater.API for actual ExESDB operations

#### 2. **Subscription System**
Two-tier subscription architecture for different use cases:

**SubscriptionProxy** (`lib/commanded/adapter/subscription_proxy.ex`):
- Handles persistent subscriptions to `$all` stream or category streams
- Converts ExESDB events to Commanded format
- Provides supervision and fault tolerance
- Manages PID re-registration for leader election scenarios

**AggregateListener** (`lib/commanded/aggregate_listener.ex`):
- Handles transient subscriptions for individual aggregate streams
- Uses Phoenix PubSub for real-time event delivery
- Provides historical event replay capability
- Filters events by specific stream IDs

#### 3. **Event Conversion Pipeline**
- **EventConverter**: Transforms ExESDB.Schema.EventRecord → Commanded.EventStore.RecordedEvent
- **Mapper**: Handles bidirectional mapping between formats
- **EventTypeMapper Behaviour**: Allows custom event type string generation

#### 4. **Supervision and Reliability**
- **AggregateListenerSupervisor**: Manages aggregate listener processes
- **SubscriptionProxySupervisor**: Manages subscription proxy processes  
- **SubscriptionGuard**: Circuit breaker for subscription registration failures
- **SubscriptionMetrics**: Tracks registration success/failure rates

### Key Architectural Patterns

#### Store-Aware Design
The adapter supports multiple ExESDB stores within the same application:
- All supervisors and processes use `store_id` prefixing
- Registry isolation prevents naming conflicts
- Logging includes store identification for debugging

#### Event Type Mapping
Custom event type mapping through behaviour implementation:
```elixir
defmodule MyApp.EventTypeMapper do
  @behaviour ExESDB.Commanded.EventTypeMapper
  
  def to_event_type(MyApp.Events.UserRegistered), do: "user_registered:v1"
  def to_event_type(MyApp.Events.EmailVerified), do: "email_verified:v1"
end
```

#### Subscription Strategy
- **Individual Streams**: Use AggregateListener with PubSub filtering
- **Category/All Streams**: Use SubscriptionProxy with direct ExESDB subscriptions
- **Stream Filtering**: Uses `StreamHelper.allowed_stream?/1` to determine subscription type

## Configuration Requirements

### Commanded Application Setup

```elixir
# config/config.exs
config :my_app, MyApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: MyApp.EventTypeMapper,
    store_id: :my_store,
    stream_prefix: "my_app_",
    serializer: Jason
  ]
```

### Required Event Type Mapper

The adapter requires an EventTypeMapper implementation:

```elixir
defmodule MyApp.EventTypeMapper do
  @behaviour ExESDB.Commanded.EventTypeMapper
  
  def to_event_type(event_module) when is_atom(event_module) do
    event_module
    |> to_string()
    |> String.replace("Elixir.", "")
  end
end
```

## Testing Strategy

### Unit Tests
- Focus on individual components (adapters, converters, helpers)
- Mock ExESDB interactions using Mox
- Test error conditions and edge cases
- Located in `test/commanded/` directory

### Integration Tests
- Require actual ExESDB.System v0.4.1 instance
- Test complete event lifecycle: append → retrieve → restart resilience
- Validate timeout prevention and concurrent operations  
- Located in `test/integration/` directory
- Use `IntegrationTestHelper` for test data management

### Test Configuration
- Integration tests tagged with `@moduletag :integration`
- 120-second timeouts for integration tests
- Automatic cleanup of test data directories
- Random port allocation to prevent CI conflicts

## Development Guidelines

### Code Patterns

#### Error Handling
- Use `StreamHelper.map_error/1` for consistent error mapping
- Log errors with store_id context for debugging
- Provide fallback behavior for non-critical failures

#### Logging Strategy
- Include store_id and component name in log messages
- Use structured logging for better searchability
- Different log levels: debug for trace info, info for key events, error for failures

#### Process Naming
- Use store-aware naming: `{:global, {store_id, name}}`
- Hash-based naming for aggregate listeners
- Registry isolation per store

### Version Compatibility
- **Elixir**: Requires >= 1.17
- **Commanded**: Compatible with ~> 1.4.8
- **ExESDB**: Development/test dependency on ~> 0.4.1
- **ExESDBGater**: Runtime dependency on ~> 0.8

### Event Sourcing Considerations

#### Stream Naming
- Prefix all streams with configured `stream_prefix`
- Use Commanded's standard stream naming conventions
- Aggregate streams: `{prefix}{aggregate_type}-{aggregate_id}`

#### Version Management  
- Commanded uses 1-based versioning
- ExESDB uses 0-based versioning
- Adapter handles conversion in `StreamHelper.normalize_expected_version/1`

#### Snapshot Handling
- Snapshots stored with `snapshots-{source_uuid}` stream naming
- Uses ExESDB's snapshot API for persistence
- Automatic latest snapshot retrieval using `source_version` sorting

## Troubleshooting

### Common Issues

#### Subscription Registration Failures
- Check ExESDB.System is running and accessible
- Verify store_id matches ExESDB configuration  
- Monitor SubscriptionGuard circuit breaker state
- Check logs for PID re-registration attempts

#### Event Type Mapping Errors
- Ensure EventTypeMapper module implements required behaviour
- Validate `to_event_type/1` function is exported
- Check for missing event type mappings in mapper implementation

#### Integration Test Failures
- Verify ExESDB v0.4.1 dependency is available
- Check ports 2113+ are available for test instances
- Ensure `/tmp/` directory has write permissions
- Validate test data cleanup between runs

### Debugging Commands

```bash
# Check subscription status
iex -S mix
iex> ExESDB.Commanded.AggregateListenerSupervisor.stats(:my_store)
iex> ExESDB.Commanded.Adapter.SubscriptionProxySupervisor.list_proxies(:my_store)

# Enable debug logging
config :logger, level: :debug

# Run single integration test with full output
mix test test/integration/adapter_integration_test.exs:53 --trace --seed 0
```

### Performance Monitoring
- Monitor subscription proxy re-registration frequency
- Track event conversion performance in high-volume scenarios
- Watch memory usage of aggregate listeners with historical replay
- Monitor ExESDB connection pool health through gater logs

## Dependencies and Integration

### Runtime Dependencies
- **commanded**: CQRS/ES framework integration
- **ex_esdb_gater**: ExESDB API client
- **uuidv7** & **elixir_uuid**: Event ID generation
- **jason**: JSON serialization (optional)

### Development Dependencies  
- **ex_esdb**: Integration testing with real ExESDB instances
- **mox**: Mocking for unit tests
- **credo**: Code analysis and linting
- **dialyxir**: Static analysis and type checking

### ExESDB Integration Points
- **Event Storage**: Via ExESDBGater.API append/read operations
- **Subscriptions**: Direct registration with ExESDB subscription system
- **Snapshots**: Using ExESDB's snapshot persistence APIs
- **PubSub**: Phoenix PubSub integration for real-time events (`<store>:$all` topics)