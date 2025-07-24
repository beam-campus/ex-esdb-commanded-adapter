# Release Notes - ExESDB Commanded Adapter

## Store-Aware Naming Improvements

### Overview
Implemented store-aware naming and supervision for the ExESDB Commanded Adapter to support umbrella applications with multiple event stores running simultaneously without conflicts.

### Implementation Details

#### Initial Setup
- Started with a failing test suite due to missing `test_helper.exs` file
- Found `test_helper.ex` located in nested `test/support` directory instead of expected `test` directory
- Moved file to `test/test_helper.exs` and populated with basic ExUnit configuration

#### Store-Aware Functionality
- **Supervisors**: Both `AggregateListenerSupervisor` and `SubscriptionProxySupervisor` are now properly namespaced per store
- **Process Naming**: All processes include store information for better isolation and debugging
- **Registry Management**: Each store gets its own registry to prevent naming conflicts
- **Enhanced Logging**: Log messages now include store information for better traceability

#### Testing Implementation
1. **Core Tests**: Created `store_aware_test.exs` under `test/commanded` to validate:
   - Store-aware naming for supervisors
   - Correct process registration per store
   - Proper atom name generation using `Module.concat`

2. **Integration Tests**: Added `multi_store_test.exs` under `test/integration` demonstrating:
   - Multiple supervisors with different store IDs running concurrently
   - No naming conflicts between stores
   - Proper isolation of store-specific processes

#### Breaking Changes
- **API Changes**: Store ID must now be passed explicitly to several functions
- **Migration Required**: Existing code needs updates to include store parameter
- **Naming Convention**: Process names now include store identifier

#### Quality Assurance
- All tests pass successfully
- Package compiles cleanly
- Both unit and integration tests validate multi-store functionality
- Comprehensive test coverage for store-aware naming

#### Documentation
- Updated `CHANGELOG.md` with comprehensive notes
- Breaking API changes clearly documented
- Migration guidance provided for existing implementations
- Enhanced logging capabilities documented

### Result
The ExESDB Commanded Adapter now fully supports umbrella applications with multiple event stores, providing proper isolation, enhanced debugging capabilities, and conflict-free operation across different store instances.
