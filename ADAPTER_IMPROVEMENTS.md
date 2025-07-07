# ExESDB.Commanded.Adapter Improvements

Based on analysis of the commanded-extreme-adapter and current issues, here are recommended improvements:

## 1. Configuration Improvements

### Add Configuration Module
Create `ExESDB.Commanded.Config` similar to the extreme adapter:

```elixir
defmodule ExESDB.Commanded.Config do
  @moduledoc false

  def store_id(config), do: Keyword.get(config, :store_id, :ex_esdb)
  
  def stream_prefix(config) do
    prefix = Keyword.get(config, :stream_prefix, "")
    
    case String.contains?(prefix, "-") do
      true -> raise ArgumentError, ":stream_prefix cannot contain a dash (\"-\")"
      false -> prefix
    end
  end

  def serializer(config) do
    Keyword.get(config, :serializer, Jason)
  end
  
  def all_stream(config), do: "$ce-" <> stream_prefix(config)
end
```

### Fix child_spec Configuration
Update the child_spec to handle configuration more robustly:

```elixir
def child_spec(application, config) do
  # Validate required configuration
  store_id = Config.store_id(config)
  stream_prefix = Config.stream_prefix(config)
  serializer = Config.serializer(config)
  
  # Handle optional name configuration
  event_store_name = case Keyword.get(config, :name) do
    nil -> Module.concat([application, EventStore])
    name -> Module.concat([name, EventStore])
  end

  adapter_meta = %{
    store_id: store_id,
    stream_prefix: stream_prefix,
    serializer: serializer,
    application: application,
    event_store_name: event_store_name,
    all_stream: Config.all_stream(config)
  }

  # No child processes needed for ExESDB (external system)
  {:ok, [], adapter_meta}
end
```

## 2. Version Handling Improvements

### Add Proper Version Normalization
```elixir
# ExESDB uses 1-based indexing, Commanded uses 0-based
defp normalize_start_version(0), do: 1
defp normalize_start_version(start_version) when start_version > 0, do: start_version

# For expected versions in append operations
defp normalize_expected_version(:any_version), do: :any
defp normalize_expected_version(:no_stream), do: 0
defp normalize_expected_version(:stream_exists), do: :stream_exists
defp normalize_expected_version(version) when is_integer(version), do: version
```

### Improve stream_forward Implementation
```elixir
def stream_forward(adapter_meta, stream_uuid, start_version, read_batch_size) do
  store = Config.store_id(adapter_meta)
  prefix = Config.stream_prefix(adapter_meta)
  full_stream_id = prefix <> stream_uuid
  
  normalized_start = normalize_start_version(start_version)
  
  case API.get_events(store, full_stream_id, normalized_start, read_batch_size, :forward) do
    {:ok, []} ->
      []
      
    {:ok, events} when is_list(events) ->
      events
      |> Stream.map(&Mapper.to_recorded_event/1)
      |> Stream.map(&normalize_event_version/1)
      
    {:error, :stream_not_found} ->
      {:error, :stream_not_found}
      
    {:error, reason} ->
      {:error, reason}
  end
end

# Normalize ExESDB 1-based versions to Commanded 0-based
defp normalize_event_version(%RecordedEvent{} = event) do
  %{event | 
    event_number: max(0, event.event_number - 1),
    stream_version: max(0, event.stream_version - 1)
  }
end
```

## 3. Error Handling Improvements

### Better append_to_stream Error Handling
```elixir
def append_to_stream(adapter_meta, stream_uuid, expected_version, events, _opts) do
  store = Config.store_id(adapter_meta)
  prefix = Config.stream_prefix(adapter_meta)
  full_stream_id = prefix <> stream_uuid
  
  new_events = Enum.map(events, &Mapper.to_new_event/1)
  normalized_expected = normalize_expected_version(expected_version)
  
  case API.append_events(store, full_stream_id, normalized_expected, new_events) do
    {:ok, _new_version} -> 
      :ok
      
    {:error, :wrong_expected_version} ->
      case expected_version do
        :no_stream -> {:error, :stream_exists}
        :stream_exists -> {:error, :stream_does_not_exist}
        _ -> {:error, :wrong_expected_version}
      end
      
    {:error, :stream_not_found} when expected_version == :stream_exists ->
      {:error, :stream_does_not_exist}
      
    {:error, reason} -> 
      {:error, reason}
  end
end
```

## 4. Libcluster Integration Improvements

Since you prefer libcluster over seed_nodes, ensure the ExESDB configuration properly uses libcluster for node discovery:

### In config/config.exs:
```elixir
config :libcluster,
  topologies: [
    ex_esdb_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1,
        secret: "your_cluster_secret"
      ]
    ]
  ]

# Remove any seed_nodes configuration from ExESDB
config :ex_esdb_gater, :ex_esdb,
  # Don't use seed_nodes - let libcluster handle discovery
  connection_string: System.get_env("ESDB_CONNECTION_STRING", "esdb://localhost:2113"),
  # Other ExESDB configuration...
```

## 5. Snapshotting Configuration Fix

The current issue with snapshotting configuration should be resolved by:

1. **Using map format instead of keyword list**:
   ```elixir
   snapshotting: %{snapshot_every: false}
   ```

2. **Adding proper snapshot support** (if needed):
   ```elixir
   def record_snapshot(adapter_meta, %SnapshotData{} = snapshot) do
     store = Config.store_id(adapter_meta)
     record = Mapper.to_snapshot_record(snapshot)
     
     # Use a consistent snapshot stream naming convention
     snapshot_stream = Config.stream_prefix(adapter_meta) <> "snapshot-" <> snapshot.source_uuid
     
     case API.record_snapshot(store, snapshot.source_uuid, snapshot_stream, snapshot.source_version, record) do
       :ok -> :ok
       {:error, reason} -> {:error, reason}
     end
   end
   ```

## 6. Testing Improvements

Add comprehensive tests similar to the extreme adapter:

```elixir
defmodule ExESDB.Commanded.AdapterTest do
  use ExUnit.Case
  
  describe "configuration" do
    test "validates stream_prefix doesn't contain dash" do
      assert_raise ArgumentError, fn ->
        ExESDB.Commanded.Config.stream_prefix(stream_prefix: "invalid-prefix")
      end
    end
  end
  
  describe "version handling" do
    test "normalizes start versions correctly" do
      # Test version normalization
    end
    
    test "handles expected version conflicts" do
      # Test error mapping
    end
  end
end
```

## Implementation Priority

1. **High Priority**: Fix snapshotting configuration format (DONE)
2. **High Priority**: Improve version normalization and error handling
3. **Medium Priority**: Add configuration validation module
4. **Medium Priority**: Enhance stream_forward robustness  
5. **Low Priority**: Add comprehensive testing

These improvements will make the ExESDB adapter more robust and compatible with Commanded's expectations while maintaining the libcluster-based approach you prefer.
