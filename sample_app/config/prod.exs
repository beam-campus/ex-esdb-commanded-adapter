import Config

config :logger, :console,
  format: "$time [$level] $message\n",
  metadata: [:mfa],
  level: :info

config :sample_app, :ex_esdb,
  data_dir: "/data/sample_app",
  store_id: :sample_app_prod,
  timeout: 5_000,
  db_type: :cluster,
  pub_sub: :sample_app_pubsub

config :ex_esdb, :logger, level: :info
config :ex_esdb_gater, :logger, level: :info
