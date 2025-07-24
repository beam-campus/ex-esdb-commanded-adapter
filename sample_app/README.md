# SampleApp

A comprehensive **event-sourced voting system** sample application for ExESDB and ExESDB Commanded Adapter integration.

This application demonstrates how to build a complete business domain using:
- **ExESDB**: A BEAM-native event store built on Khepri
- **ExESDB Commanded Adapter**: Integration with the Commanded CQRS/ES framework
- **Event Sourcing**: All state changes captured as immutable events
- **CQRS**: Clean separation of command and query responsibilities
- **Domain-Driven Design**: Business-focused vertical slicing architecture
- **Cluster mode**: Using libcluster for node discovery (preferred over seed_nodes)

## Configuration

The application is configured to run ExESDB in cluster mode with the following key settings:

- **Store ID**: `:sample_app` (dev: `:sample_app_dev`, test: `:sample_app_test`)
- **Data Directory**: `tmp/sample_app` (configurable per environment)
- **DB Type**: `:cluster` (development/production), `:single` (test)
- **PubSub**: `:sample_app_pubsub`
- **Clustering**: Uses libcluster with Gossip strategy

### Key Files

- `config/config.exs` - Main configuration
- `config/dev.exs` - Development-specific settings
- `config/runtime.exs` - Runtime configuration with environment variable support
- `lib/sample_app/commanded_app.ex` - Commanded application setup
- `lib/sample_app/event_type_mapper.ex` - Event type mapping for serialization

## Running

```bash
# Fetch dependencies
mix deps.get

# Start the application
mix run --no-halt

# Or in interactive mode
iex -S mix
```

## Environment Variables

The application supports runtime configuration via environment variables:

- `EX_ESDB_STORE_ID` - Override the store ID
- `EX_ESDB_DATA_DIR` - Override the data directory
- `EX_ESDB_DB_TYPE` - Override the database type (single/cluster)
- `EX_ESDB_TIMEOUT` - Override the timeout value
- `EX_ESDB_CLUSTER_SECRET` - Cluster secret for node authentication

## 🗳️ Voting System Domain

This sample app implements a **complete event-sourced voting system** following Domain-Driven Design principles and event storming methodology.

### 🧩 Architecture Features

- **📐 Vertical Slicing** - Each feature completely isolated in its own folder
- **📢 Screaming Architecture** - Business intent clearly visible from directory structure  
- **🎯 Event Sourcing** - All state changes captured as immutable events
- **🏛️ CQRS** - Clean separation of command and query responsibilities
- **📋 Business Rules** - Comprehensive validation and constraint enforcement
- **🔄 Event-Driven Policies** - Automatic reactions to business events
- **🧪 Test Coverage** - 69 comprehensive tests covering all scenarios

### 📋 Implemented Vertical Slices

1. **🆕 `initialize_poll`** - Create new polls with options and expiration
   - Command: `InitializePoll.CommandV1`
   - Event: `InitializePoll.EventV1`
   - Handler: `MaybeInitializePollV1`
   - State: `InitializedToStateV1`

2. **🗳️ `cast_vote`** - Allow users to vote on poll options
   - Command: `CastVote.CommandV1`
   - Event: `CastVote.EventV1`
   - Handler: `MaybeCastVoteV1`
   - State: `CastedToStateV1`

3. **🔒 `close_poll`** - Manually close polls before expiration
   - Command: `ClosePoll.CommandV1`
   - Event: `ClosePoll.EventV1`
   - Handler: `MaybeClosePollV1`
   - State: `ClosedToStateV1`

4. **⏱️ `expire_countdown`** - Automatically expire polls when time runs out
   - Command: `ExpireCountdown.CommandV1`
   - Event: `ExpireCountdown.EventV1`
   - Handler: `MaybeExpireCountdownV1`
   - State: `EventHandlerV1`

5. **⏰ `start_expiration_countdown`** - Start automated expiration tracking
   - Command: `StartExpirationCountdown.CommandV1`
   - Event: `StartExpirationCountdown.EventV1`
   - Handler: `MaybeStartExpirationCountdownV1`
   - State: `CountdownStartedToStateV1`
   - Policy: `WhenPollInitializedThenStartExpirationCountdownV1`

### 🎯 Business Capabilities

- ✅ Create polls with multiple options
- ✅ Set expiration times for automatic closure
- ✅ Cast votes with duplicate prevention
- ✅ Manual poll closure by creators
- ✅ Automatic expiration countdown management
- ✅ Comprehensive business rule enforcement

### 📊 Test Results

- **✅ 68 Unit Tests** - All passing
- **✅ 1 Doctest** - Passing  
- **🔬 Integration Tests** - Implemented

```bash
# Run all tests
mix test

# Run unit tests only (excluding integration)
mix test --exclude integration

# Run specific test file
mix test test/sample_app/domain/initialize_poll_test.exs
```

## 🎮 Interactive REPL Interface

The application includes a user-friendly REPL interface for interactive exploration and testing.

### Getting Started

```bash
# Start the interactive shell
iex -S mix

# The system automatically loads with helpful aliases:
# - Voting (alias for SampleApp.VotingREPL)
# - Welcome (alias for SampleApp.REPLWelcome)
```

### Quick Demo

```elixir
# Run a complete demo
Welcome.demo()

# Or try commands manually:
Voting.create_poll("Favorite Language?", ["Elixir", "Rust", "Go"])
Voting.vote("poll-123", "option_1", "alice")
Voting.list_polls()
```

### Available Commands

| Command | Description | Example |
|---------|-------------|----------|
| `Voting.help()` | Show all commands | `Voting.help()` |
| `Voting.create_poll/3` | Create new poll | `Voting.create_poll("Title", ["A", "B"])` |
| `Voting.create_poll_with_expiration/4` | Create expiring poll | `Voting.create_poll_with_expiration("Quick", ["Yes", "No"], 3600)` |
| `Voting.vote/3` | Cast a vote | `Voting.vote("poll-123", "option_1", "alice")` |
| `Voting.close_poll/2` | Close poll manually | `Voting.close_poll("poll-123")` |
| `Voting.list_polls/0` | List session polls | `Voting.list_polls()` |
| `Voting.poll_info/1` | Detailed poll info | `Voting.poll_info("poll-123")` |
| `Voting.expire_poll/1` | Manually expire poll | `Voting.expire_poll("poll-123")` |

### Key Features

- 🎯 **User-friendly** - Natural language function names
- 📋 **Session tracking** - Keeps track of polls created in your session
- ✅ **Rich feedback** - Clear success/error messages with emojis
- 🎬 **Demo mode** - Complete demo showing all features
- 📊 **Status display** - Shows poll status, expiration, and options
- 💡 **Helpful hints** - Guidance for valid option IDs and commands

