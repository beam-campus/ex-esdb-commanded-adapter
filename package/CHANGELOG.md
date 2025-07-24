# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2025-07-20

### Changed

- **BREAKING**: Refactored EventTypeMapper to use behavior-based approach instead of process dictionary
- **BREAKING**: EventTypeMappers must now implement `ExESDB.Commanded.EventTypeMapper` behaviour
- Removed dynamic event type mapping in favor of explicit function clauses
- Improved error messages for missing or invalid event type mappers
- Better validation of event type mapper configuration at startup

### Added

- `ExESDB.Commanded.EventTypeMapper` behaviour defining the required interface
- Comprehensive documentation for implementing event type mappers
- Early validation of event type mapper implementations
- Clearer error messages for event type mapping failures

### Fixed

- Process dictionary-based event type mapping which could cause issues in certain scenarios
- Potential race conditions in event type mapper configuration
- Unclear error messages when event type mapper was misconfigured

### Migration Guide

`EventTypeMappers` must now implement the `ExESDB.Commanded.EventTypeMapper` behaviour:

```elixir
# In your application's config/config.exs:
config :my_app, MyApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: MyApp.EventTypeMapper,
    store_id: :my_store,
    # ... other config
  ]

# In lib/my_app/event_type_mapper.ex:
defmodule MyApp.EventTypeMapper do
  @behaviour ExESDB.Commanded.EventTypeMapper

  # Explicit function clauses for each event type
  def to_event_type(MyApp.Events.UserRegistered), do: "user_registered:v1"
  def to_event_type(MyApp.Events.EmailVerified), do: "email_verified:v1"

  # Fallback for unknown event types
  def to_event_type(unknown_event) do
    raise "Unknown event type: #{inspect(unknown_event)}"
  end
end
```

## [0.2.4] - 2025-07-18

### Added

- **Comprehensive Integration Test Suite**: Complete integration tests validating adapter behavior with real ExESDB.System instances
- **Test Suite Documentation**: Detailed guide (`guides/test-suite.md`) covering unit tests, integration tests, and testing best practices
- **Integration Test Helper**: Utility module (`test/support/integration_test_helper.ex`) for system management and test data creation
- **ExESDB v0.4.1 Dependency**: Added for test and development environments only
- **Test Coverage**: Validates timeout prevention, event persistence, system restart resilience, concurrent operations, and large payload handling

### Changed

- **Version Bump**: Updated version from 0.2.3 to 0.2.4
- **Documentation**: Added test suite guide to ExDoc documentation
- **Test Helper**: Enhanced test helper with conditional ExESDB startup for integration tests

### Test Suite Features

- **Timeout Prevention**: Ensures system doesn't fail due to timeouts when appending events
- **Event Persistence**: Verifies events can be retrieved after being appended
- **System Restart Resilience**: Tests that events persist across ExESDB.System restarts
- **Concurrent Operations**: Validates handling of multiple concurrent stream operations
- **Large Payload Handling**: Tests handling of events with >1KB data payloads
- **Automatic Cleanup**: Tests clean up data directories and processes automatically
- **Configurable Ports**: Uses random ports to avoid conflicts in CI/CD environments
- **Comprehensive Logging**: Detailed logging for troubleshooting and debugging

## [0.2.3] - 2025-07-18

### Fixed

- **HOTFIX**: Fixed `Enum.EmptyError` when no snapshots exist for an aggregate
- Improved guard clause in `read_snapshot/2` to properly handle empty snapshots list

## [0.2.2] - 2025-07-18

### Added

- Store-aware naming for supervisors and processes to support umbrella applications
- Enhanced logging with store identification for better debugging
- Comprehensive test suite for store-aware functionality

### Changed

- **BREAKING**: `AggregateListenerSupervisor` now requires `store_id` parameter
- **BREAKING**: `SubscriptionProxySupervisor` now requires `store_id` parameter
- **BREAKING**: `AggregateListenerSupervisor.stop_listener/1` now requires `store_id` as first parameter: `stop_listener(store_id, pid)`
- **BREAKING**: `AggregateListenerSupervisor.stats/0` now requires `store_id` parameter: `stats(store_id)`
- **BREAKING**: `AggregateListenerSupervisor.list_listeners/0` now requires `store_id` parameter: `list_listeners(store_id)`
- **BREAKING**: `SubscriptionProxySupervisor.stop_proxy/1` now requires `store_id` as first parameter: `stop_proxy(store_id, pid)`
- **BREAKING**: `SubscriptionProxySupervisor.list_proxies/0` now requires `store_id` parameter: `list_proxies(store_id)`
- `AggregateListener` processes now use store-specific Registry naming
- `SubscriptionProxy` processes now use global names with store prefixes
- All supervisors and processes now include store information in log messages
- Enhanced supervision tree isolation between different stores
- Improved `read_snapshot/2` function to properly find latest snapshots using `ExESDB.SnapshotsReader.list_snapshots/2`
- Enhanced `to_snapshot_record/1` mapper function with nil protection for `created_at` field

### Fixed

- **CRITICAL**: Snapshot loading after server restart - snapshots now properly load the latest version instead of hardcoded version 0
- Naming conflicts when multiple stores are used in umbrella applications
- Process registry conflicts between different event stores
- Supervisor name clashes in multi-store environments
- Potential crashes when `created_at` field is nil in snapshot records

### Technical Details

#### Store-Aware Supervisor Naming

- `AggregateListenerSupervisor` instances now use names like `ExESDB.Commanded.AggregateListenerSupervisor.StoreId`
- `SubscriptionProxySupervisor` instances now use names like `ExESDB.Commanded.Adapter.SubscriptionProxySupervisor.StoreId`
- Each store gets its own Registry: `ExESDB.Commanded.AggregateListenerSupervisor.StoreId.Registry`

#### Process Naming

- `AggregateListener` processes use store-specific Registry via tuples
- `SubscriptionProxy` processes use global names with store prefixes: `{:global, {store_id, name}}`

#### Logging Improvements

- All log messages now include store identification
- Format: `AggregateListener[store_id]: message` and `SubscriptionProxy[name] (store: store_id): message`

#### Migration Guide

**Before:**

```elixir
child_specs = [
  {AggregateListenerSupervisor, []},
  {SubscriptionProxySupervisor, []}
]
```

**After:**

```elixir
child_specs = [
  {AggregateListenerSupervisor, [store_id: :my_store]},
  {SubscriptionProxySupervisor, [store_id: :my_store]}
]
```

**API Changes:**

```elixir
# Before
AggregateListenerSupervisor.stop_listener(pid)
AggregateListenerSupervisor.stats()
AggregateListenerSupervisor.list_listeners()

# After
AggregateListenerSupervisor.stop_listener(:my_store, pid)
AggregateListenerSupervisor.stats(:my_store)
AggregateListenerSupervisor.list_listeners(:my_store)
```

## [0.1.4] - Previous Release

### Added

- Initial release functionality
- Basic ExESDB adapter for Commanded
- AggregateListener and SubscriptionProxy processes
- Support for event streaming and subscriptions
