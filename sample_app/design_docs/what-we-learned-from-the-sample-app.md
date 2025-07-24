# What We Learned from the Sample App

This document captures key learnings, patterns, and best practices discovered while building the Sample Voting App using ExESDB and Commanded.

## Table of Contents

- [EventTypeMapper Best Practices](#eventtypemapper-best-practices)
- [Clean Subscription Names](#clean-subscription-names)
- [Cachex Integration Patterns](#cachex-integration-patterns)
- [Projection Handler Patterns](#projection-handler-patterns)
- [Event Type Subscription Strategy](#event-type-subscription-strategy)
- [Common Pitfalls and Solutions](#common-pitfalls-and-solutions)

## EventTypeMapper Best Practices

### The Problem: Ugly Module Names in Event Storage

**Before**: The default EventTypeMapper approach just removed the "Elixir." prefix:
```elixir
# Bad - produces ugly event types
def to_event_type(module_name) when is_atom(module_name) do
  module_name
  |> to_string()
  |> String.replace("Elixir.", "")
end

# Results in: "SampleApp.Domain.CastVote.EventV1"
```

**After**: Enhanced EventTypeMapper calls `event_type()` on event modules:
```elixir
# Good - produces clean semantic event types
def to_event_type(module_name) when is_atom(module_name) do
  try do
    # Try to call event_type/0 on the module to get clean event type
    module_name.event_type()
  rescue
    # If module doesn't have event_type/0 function, fall back to module name
    _ ->
      module_name
      |> to_string()
      |> String.replace("Elixir.", "")
  end
end

# Results in: "vote_casted:v1"
```

### Event Module Pattern

Every event module should define a clean `event_type/0` function:

```elixir
defmodule SampleApp.Domain.CastVote.EventV1 do
  @derive Jason.Encoder
  defstruct [:poll_id, :option_id, :voter_id, :voted_at, :version]
  
  # This is crucial for clean event types!
  def event_type, do: "vote_casted:v1"
end
```

**Key Benefits:**
- ✅ Clean event types in storage: `"vote_casted:v1"`
- ✅ Semantic versioning support: `:v1`, `:v2`, etc.
- ✅ Professional topic names in ExESDB
- ✅ Easier debugging and monitoring

## Clean Subscription Names

### The Problem: Module Names as Subscription Identifiers

**Before**: Using module names created ugly subscription topics:
```elixir
use Commanded.Event.Handler,
  application: SampleApp.CommandedApp,
  name: "SampleApp.Domain.CastVote.CastedToResultsV1",  # Ugly!
  subscribe_to: "$et-vote_casted:v1"

# Resulted in topic: "sample_app_dev:*SampleApp.Domain.CastVote.CastedToResultsV1-vote_casted:v1"
```

**After**: Using clean, semantic subscription names:
```elixir
use Commanded.Event.Handler,
  application: SampleApp.CommandedApp,
  name: "vote_casted_to_results_v1",  # Clean and readable!
  subscribe_to: "$et-vote_casted:v1"

# Results in topic: "sample_app_dev:*vote_casted_to_results_v1-vote_casted:v1"
```

### Subscription Naming Conventions

Follow these patterns for consistent, readable subscription names:

| Pattern | Example | Use Case |
|---------|---------|----------|
| `<event>_to_<target>_v<n>` | `vote_casted_to_summary_v1` | Projections |
| `<event>_to_<target>_v<n>` | `poll_initialized_to_results_v1` | Read model updates |
| `<trigger>_<action>_policy_v<n>` | `poll_initialized_start_countdown_policy_v1` | Business policies |

**Benefits:**
- ✅ Clean ExESDB topic names for monitoring
- ✅ Easy to understand subscription purpose
- ✅ Consistent naming across the system
- ✅ Version-aware subscription management

## Cachex Integration Patterns

### Handling Multiple Cachex Return Patterns

**Discovery**: `Cachex.get_and_update/3` can return different patterns depending on the operation:
- `{:ok, {old_value, new_value}}` - Standard operation
- `{:commit, {old_value, new_value}}` - Transaction operation

**Solution**: Handle both patterns in projections:

```elixir
def handle(%VoteCastedEvent{} = event, _metadata) do
  update_func = fn
    nil -> {nil, nil}  # Handle missing data
    %PollSummary{} = summary ->
      updated_summary = PollSummary.add_vote(summary, event.option_id)
      {summary, updated_summary}
  end
  
  case Cachex.get_and_update(:poll_summaries, event.poll_id, update_func) do
    # Handle both possible return patterns
    {:ok, {_old_value, %PollSummary{} = _updated_summary}} ->
      Logger.info("✅ Poll summary updated successfully")
      :ok
      
    {:commit, {_old_value, %PollSummary{} = _updated_summary}} ->
      Logger.info("✅ Poll summary updated successfully") 
      :ok
      
    {:ok, {nil, nil}} ->
      Logger.warning("⚠️ Poll summary not found")
      {:error, :poll_summary_not_found}
      
    {:commit, {nil, nil}} ->
      Logger.warning("⚠️ Poll summary not found")
      {:error, :poll_summary_not_found}
      
    {:error, reason} ->
      Logger.error("❌ Failed to update poll summary: #{inspect(reason)}")
      {:error, reason}
  end
end
```

### Projection Function Patterns

**Avoid**: Using captured functions with closure variables:
```elixir
# Bad - causes runtime errors
case Cachex.get_and_update(:cache, key, &update_function(&1, external_var)) do
```

**Use**: Inline anonymous functions that capture the closure properly:
```elixir
# Good - captures closure correctly
update_func = fn
  nil -> handle_nil_case()
  existing_value -> handle_existing_case(existing_value, external_var)
end

case Cachex.get_and_update(:cache, key, update_func) do
```

## Event Type Subscription Strategy

### Per-Event-Type Subscriptions vs. Global Stream

**Recommended**: Subscribe to specific event types using the `$et-<event_type>` pattern:

```elixir
# Good - targeted subscriptions
use Commanded.Event.Handler,
  subscribe_to: "$et-vote_casted:v1"  # Only vote events

use Commanded.Event.Handler,
  subscribe_to: "$et-poll_initialized:v1"  # Only poll init events
```

**Avoid**: Subscribing to the global `$all` stream:
```elixir
# Avoid - receives all events, less efficient
use Commanded.Event.Handler,
  subscribe_to: "$all"
```

**Benefits of Per-Event-Type Subscriptions:**
- ✅ Better performance (only relevant events)
- ✅ Cleaner topic names in ExESDB
- ✅ Easier monitoring and debugging
- ✅ Natural separation of concerns
- ✅ Supports event-type-specific scaling

### ExESDB Topic Pattern

The final topic pattern in ExESDB follows this structure:
```
"<store_id>:*<subscription_name>-<event_type>"
```

Examples:
- `"sample_app_dev:*vote_casted_to_summary_v1-vote_casted:v1"`
- `"sample_app_dev:*poll_initialized_to_results_v1-poll_initialized:v1"`
- `"sample_app_dev:*poll_initialized_start_countdown_policy_v1-poll_initialized:v1"`

## Projection Handler Patterns

### Vertical Slice Architecture

**Pattern**: Place projection handlers in the same domain slice as the events they process:

```
lib/sample_app/domain/
├── cast_vote/
│   ├── event_v1.ex                    # Event definition
│   ├── casted_to_summary_v1.ex        # Projection: event → summary
│   ├── casted_to_results_v1.ex        # Projection: event → results  
│   └── casted_to_voter_history_v1.ex  # Projection: event → history
├── initialize_poll/
│   ├── event_v1.ex                    # Event definition
│   ├── initialized_to_summary_v1.ex   # Projection: event → summary
│   └── initialized_to_results_v1.ex   # Projection: event → results
```

**Benefits:**
- ✅ Clear coupling between events and their handlers
- ✅ Easy to find all handlers for a specific event
- ✅ Domain knowledge stays within the slice
- ✅ Easier refactoring and maintenance

### Handler Naming Convention

Follow this pattern for handler module names:
- `<EventName>To<TargetName>V<Version>`
- Example: `CastedToSummaryV1`, `InitializedToResultsV1`

### Error Handling Pattern

**Standard pattern** for projection error handling:

```elixir
def handle(%SomeEvent{} = event, _metadata) do
  Logger.info("🎯 Processing #{event.event_type} for ID: #{event.aggregate_id}")
  
  case perform_projection_logic(event) do
    :ok ->
      Logger.info("✅ Projection completed successfully")
      :ok
      
    {:error, :not_found} ->
      Logger.warning("⚠️ Target not found - may be normal for some events")
      {:error, :not_found}
      
    {:error, reason} ->
      Logger.error("❌ Projection failed: #{inspect(reason)}")
      {:error, reason}
  end
end
```

## Common Pitfalls and Solutions

### 1. Function Capture with External Variables

**Pitfall**: Using `&function(&1, var)` with external variables:
```elixir
# Bad - runtime error
case Cachex.get_and_update(:cache, key, &update_with_vote(&1, event.option_id)) do
```

**Solution**: Use anonymous functions:
```elixir
# Good - captures closure properly
update_func = fn value -> update_with_vote(value, event.option_id) end
case Cachex.get_and_update(:cache, key, update_func) do
```

### 2. Missing EventTypeMapper Configuration

**Pitfall**: Forgetting to configure the EventTypeMapper in Commanded:
```elixir
# Missing event_type_mapper causes ugly module names
config :sample_app, SampleApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    # event_type_mapper: SampleApp.EventTypeMapper,  # Missing!
  ]
```

**Solution**: Always configure the EventTypeMapper:
```elixir
config :sample_app, SampleApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: SampleApp.EventTypeMapper,  # Essential!
  ]
```

### 3. Inconsistent Return Pattern Handling

**Pitfall**: Only handling `{:commit, ...}` patterns:
```elixir
# Bad - misses {:ok, ...} patterns
case Cachex.get_and_update(...) do
  {:commit, result} -> handle_result(result)
  # Missing {:ok, result} pattern!
end
```

**Solution**: Handle both patterns:
```elixir
# Good - handles all possible patterns
case Cachex.get_and_update(...) do
  {:ok, result} -> handle_result(result)
  {:commit, result} -> handle_result(result)
  {:error, reason} -> handle_error(reason)
end
```

### 4. Missing event_type/0 Functions

**Pitfall**: Event modules without `event_type/0` functions:
```elixir
defmodule MyEvent do
  defstruct [:id, :data]
  # Missing event_type/0 function!
end
```

**Solution**: Always define semantic event types:
```elixir
defmodule MyEvent do
  defstruct [:id, :data]
  
  def event_type, do: "my_event:v1"  # Clean and semantic!
end
```

## Summary

The key learnings from building the Sample Voting App:

1. **EventTypeMapper Enhancement** - Call `event_type/0` on modules for clean event types
2. **Clean Subscription Names** - Use semantic names instead of module names
3. **Robust Cachex Patterns** - Handle both `{:ok, ...}` and `{:commit, ...}` return patterns
4. **Per-Event-Type Subscriptions** - Use `$et-<event_type>` instead of `$all`
5. **Vertical Slice Architecture** - Keep event handlers with their events
6. **Consistent Naming Conventions** - Follow established patterns for predictability

These patterns result in:
- ✅ Clean, professional topic names in ExESDB
- ✅ Robust projection handlers that don't crash
- ✅ Easy-to-understand subscription architecture
- ✅ Maintainable codebase with clear separation of concerns
- ✅ Excellent debugging and monitoring experience

The investment in proper EventTypeMapper implementation and clean subscription names pays dividends in system observability, maintainability, and developer experience.
