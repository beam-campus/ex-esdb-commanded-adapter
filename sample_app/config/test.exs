import Config

config :logger, :console,
  format: "$time [$level] $message\n",
  metadata: [:mfa],
  level: :warning

config :sample_app, :ex_esdb,
  data_dir: "tmp/sample_app_test",
  store_id: :sample_app_test,
  timeout: 5_000,
  # Use single mode for faster tests
  db_type: :single,
  pub_sub: :sample_app_test_pubsub

# Configure Phoenix PubSub for test environment
config :phoenix_pubsub,
  :sample_app_test_pubsub, []

config :ex_esdb, :logger, level: :warning
config :ex_esdb_gater, :logger, level: :warning
