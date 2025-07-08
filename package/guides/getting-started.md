### Getting Started Guide

---

## Introduction

Welcome to the ExESDB Commanded Adapter! This guide will walk you through setting up the adapter to work with your Commanded application using ExESDB as your event store.

## Prerequisites

- **Elixir Version:** Ensure your Elixir environment is 1.17 or newer.
- **Commanded Library:** This package acts as an adapter for Commanded, so you'll need to have it set up in your Elixir project.

## Installation

Add the adapter to your Mix dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_esdb_commanded, "~> 0.1.0"},
  ]
end
```

Run `mix deps.get` to fetch the dependency.

## Configuration

Configuration can be done in your `config/config.exs` file.

### Basic Configuration

Add the following configuration to specify the adapter for your Commanded application:

```elixir
config :my_app, MyApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    store_id: :my_store_id,
    stream_prefix: "my_app_",
    event_type_mapper: MyApp.EventTypeMapper
  ]
```

### Environment Variables

Make sure to check environment variables for dynamic configurations:

- `EXESDB_COMMANDED_STORE_ID`
- `EXESDB_COMMANDED_STREAM_PREFIX`

Set these accordingly in your environment or `runtime.exs`.

### Advanced Options

You can also tweak other settings like connection timeout, retry attempts, and backoff intervals:

```elixir
config :ex_esdb_commanded_adapter,
  connection_timeout: 15_000,
  retry_attempts: 5,
  retry_backoff: 1_500
```

## Using the Adapter

1. **Start Your ExESDB Instance:** Ensure your ExESDB instance is running and reachable.
2. **Initialize Commanded:** Once configured, Commanded will use the ExESDB adapter for event storage.

3. **Event Handling:** Use your registered event type mapper to handle event types efficiently.

## Debugging and Logs

Enable detailed logging to troubleshoot:

```elixir
config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:mfa, :request_id]
```

Check logs for information on event handling and adapter performance.

## Summary

Congratulations! You’ve set up and configured the ExESDB Commanded Adapter in your project. Enjoy a seamless event-driven architecture with the power of Commanded and ExESDB.

---
