import Config

config :logger, :console,
  format: "$time ($metadata) [$level] $message\n",
  metadata: [:mfa],
  level: :info

config :ex_esdb, :logger, level: :debug
