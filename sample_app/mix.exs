defmodule SampleApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :sample_app,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :phoenix_pubsub],
      mod: {SampleApp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_esdb_gater, path: "../../ex-esdb-gater/system/", override: true},
      {:ex_esdb_commanded, path: "../package/"},
      {:ex_esdb, path: "../../ex-esdb/package/"},
      {:cachex, "~> 3.6"},
      
      # Property-based testing
      {:stream_data, "~> 0.6", only: [:test, :dev]}
    ]
  end
end
