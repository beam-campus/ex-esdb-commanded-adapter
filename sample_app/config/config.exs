# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

import Config

# Configure the logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:mfa]

# Configure specific modules' log levels - reduce noise from Swarm, Ra, and Khepri
config :logger,
  compile_time_purge_matching: [
    # Swarm modules - only show errors
    [module: Swarm.Distribution.Ring, level_lower_than: :error],
    [module: Swarm.Distribution.Strategy, level_lower_than: :error],
    [module: Swarm.Registry, level_lower_than: :error],
    [module: Swarm.Tracker, level_lower_than: :error],
    [module: Swarm.Distribution.StaticQuorumRing, level_lower_than: :error],
    [module: Swarm.Distribution.Handler, level_lower_than: :error],
    [module: Swarm.IntervalTreeClock, level_lower_than: :error],
    [module: Swarm.Logger, level_lower_than: :error],
    [module: Swarm, level_lower_than: :error]
  ]

# Configure ExESDB for the sample app
config :sample_app, :ex_esdb,
  data_dir: "tmp/sample_app",
  store_id: :sample_app,
  timeout: 10_000,
  # Use single-node mode for reliable startup and testing
  db_type: :single,
  pub_sub: :sample_app_pubsub,
  store_description: "Sample App - ExESDB Testing Application",
  store_tags: ["development", "single-node", "sample", "testing"]

# Configure Phoenix PubSub for the sample app
config :phoenix_pubsub,
  :sample_app_pubsub, []

# Configure Commanded app with ExESDB adapter
config :sample_app, SampleApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: SampleApp.EventTypeMapper,
    store_id: :sample_app,
    stream_prefix: "sample_app_",
    serializer: Jason,
    log_level: :info
  ]

# Configure ex_esdb_gater for API access
config :ex_esdb_gater, :api,
  pub_sub: :sample_app_pubsub

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
