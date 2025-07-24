import Config

# Runtime configuration
# This file is executed when the release starts up, not during compilation.
# It loads configuration from environment variables and other runtime sources.

# Configure libcluster for cluster mode
# Following the rule to use libcluster instead of seed_nodes
if config_env() != :test do
  config :libcluster,
    topologies: [
      sample_app_gossip: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          # Use multicast for local development
          multicast_addr: {255, 255, 255, 255},
          multicast_ttl: 1,
          # Use the configured cluster secret from environment
          secret: System.get_env("EX_ESDB_CLUSTER_SECRET", "sample_app_cluster_secret_2025"),
          port: 45892
        ]
      ]
    ]
end

# Override configuration from environment variables if available
if System.get_env("EX_ESDB_STORE_ID") do
  config :sample_app, :ex_esdb,
    store_id: String.to_atom(System.get_env("EX_ESDB_STORE_ID"))
end

if System.get_env("EX_ESDB_DATA_DIR") do
  config :sample_app, :ex_esdb,
    data_dir: System.get_env("EX_ESDB_DATA_DIR")
end

if System.get_env("EX_ESDB_DB_TYPE") do
  config :sample_app, :ex_esdb,
    db_type: String.to_atom(System.get_env("EX_ESDB_DB_TYPE"))
end

if System.get_env("EX_ESDB_TIMEOUT") do
  config :sample_app, :ex_esdb,
    timeout: String.to_integer(System.get_env("EX_ESDB_TIMEOUT"))
end
