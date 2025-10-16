import Config

config :ex_unit,
  capture_log: false,
  assert_receive_timeout: 5_000,
  refute_receive_timeout: 1_000,
  exclude: [:skip],
  logger: true

# Configure ExESDB for testing with minimal setup
config :ex_esdb,
  enabled: false

config :ex_esdb_gater,
  enabled: false

# Configure ExESDB.Commanded for testing
config :ex_esdb_commanded, ExESDB.Commanded.ProjectionsRebuilderIntegrationTest.TestApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: ExESDB.Commanded.EventTypeMapper,
    store_id: :test_store,
    stream_prefix: "test_",
    log_level: :info
  ]

config :ex_esdb_commanded, :test_umbrella_app,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: ExESDB.Commanded.EventTypeMapper,
    store_id: :test_store,
    stream_prefix: "test_",
    log_level: :info
  ]
