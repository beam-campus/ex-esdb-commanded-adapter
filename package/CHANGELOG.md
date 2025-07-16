# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed
- Naming conflicts when multiple stores are used in umbrella applications
- Process registry conflicts between different event stores
- Supervisor name clashes in multi-store environments

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
