# Integration Tests

This directory contains integration tests for the ExESDB Commanded Adapter.

## Overview

The integration tests verify that the ExESDB Commanded Adapter works correctly with a real ExESDB.System instance, including:

1. **Timeout Prevention**: Ensures the system doesn't fail due to timeouts when appending events
2. **Event Persistence**: Verifies events can be retrieved after being appended
3. **System Restart Resilience**: Tests that events persist across ExESDB.System restarts
4. **Concurrent Operations**: Validates handling of multiple concurrent stream operations
5. **Large Payloads**: Tests handling of events with large data payloads

## Running Integration Tests

### Prerequisites

1. Ensure you have ExESDB v0.4.1 available as a dependency
2. Make sure you have sufficient disk space for test data in `/tmp/`
3. Ensure ports 2113+ are available for ExESDB instances

### Running Tests

```bash
# Run all integration tests
mix test --only integration

# Run integration tests with verbose output
mix test --only integration --trace

# Run with integration environment variable
INTEGRATION_TEST=true mix test --only integration

# Run a specific integration test
mix test test/integration/adapter_integration_test.exs --only integration
```

### Test Configuration

The integration tests use the following configuration:

- **Store ID**: `:integration_test_store`
- **Stream Prefix**: `"integration_test_"`
- **Data Directory**: `/tmp/exesdb_test_integration_test_store`
- **Timeout**: 120 seconds per test

### Test Structure

Each test follows the Given-When-Then pattern:

- **GIVEN**: ExESDB.System is running and adapter supervisors are started
- **WHEN**: Operations are performed via the adapter
- **THEN**: Expected outcomes are verified

### Test Cleanup

Tests automatically clean up after themselves by:

1. Stopping ExESDB.System processes
2. Removing test data directories
3. Stopping adapter supervisors

### Troubleshooting

If tests fail:

1. Check that ExESDB dependency is properly installed
2. Verify no other processes are using the test ports
3. Ensure `/tmp/` directory has write permissions
4. Check logs for specific error messages

### Test Helper

The `IntegrationTestHelper` module provides utilities for:

- Starting/stopping ExESDB.System instances
- Creating test events and large payloads
- Cleaning up test data
- Waiting for system readiness

## Test Coverage

The integration tests cover the following adapter functions:

- `append_to_stream/5`
- `stream_forward/4`
- System restart scenarios
- Concurrent operations
- Error handling
- Large payload handling

These tests ensure the adapter maintains reliability and performance under various conditions.
