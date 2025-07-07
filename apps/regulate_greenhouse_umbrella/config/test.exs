import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :regulate_greenhouse, RegulateGreenhouse.Repo,
  database: Path.expand("../regulate_greenhouse_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :regulate_greenhouse_web, RegulateGreenhouseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "DqkAkGqUABN98FzCyPJYWjvZFkTOBSWRHc0LzV63zjacBHurOunJ9rBBPXwKm9pg",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails
config :regulate_greenhouse, RegulateGreenhouse.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure ExESDB for testing
config :ex_esdb,
  data_dir: "tmp/reg_gh_test",
  store_id: :reg_gh_test,
  timeout: 2_000,
  db_type: :single,
  pub_sub: :ex_esdb_pubsub

config :ex_esdb, :khepri,
  data_dir: "tmp/reg_gh_test",
  store_id: :reg_gh_test,
  timeout: 2_000,
  db_type: :single,
  pub_sub: :ex_esdb_pubsub

# Configure the Commanded application for testing
config :regulate_greenhouse, RegulateGreenhouse.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    store_id: :reg_gh_test,
    stream_prefix: "regulate_greenhouse_",
    serializer: Jason
  ]

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
