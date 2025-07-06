import Config

config :logger, :console,
  format: "$time [$level] $message\n",
  metadata: [:mfa],
  level: :info
