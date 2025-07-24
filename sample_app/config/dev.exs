import Config

# Reduce Ra and Khepri verbosity - only show warnings and errors
config :khepri,
  log_level: :warning,
  logger: true

config :ra,
  log_level: :warning,
  logger: true

config :logger, :console,
  format: "$time ($metadata) [$level] $message\n",
  metadata: [:mfa],
  level: :info,
  # Multiple filters to reduce noise from various components
  filters: [
    ra_noise: {ExESDB.LoggerFilters, :filter_ra},
    khepri_noise: {ExESDB.LoggerFilters, :filter_khepri},
    swarm_noise: {ExESDB.LoggerFilters, :filter_swarm},
    libcluster_noise: {ExESDB.LoggerFilters, :filter_libcluster}
  ]

config :sample_app, :ex_esdb,
  data_dir: "tmp/sample_app_dev",
  store_id: :sample_app_dev,
  timeout: 10_000,
  # Use single-node mode for reliable startup and testing
  db_type: :single,
  pub_sub: :sample_app_pubsub

# Override Commanded config for dev to match ExESDB store_id
config :sample_app, SampleApp.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    event_type_mapper: SampleApp.EventTypeMapper,
    store_id: :sample_app_dev,
    stream_prefix: "sample_app_",
    serializer: Jason,
    log_level: :info
  ]

# Reduce Swarm logging noise - only show true errors
config :swarm,
  log_level: :error,
  logger: true

# Runtime filtering for any remaining Swarm noise
config :logger,
  level: :info,
  backends: [:console],
  handle_otp_reports: true,
  handle_sasl_reports: false

config :ex_esdb, :logger, level: :debug
config :ex_esdb_gater, :logger, level: :debug
