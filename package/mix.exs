defmodule ExESDB.Commanded.MixProject do
  @moduledoc false
  use Mix.Project

  @app_name :ex_esdb_commanded
  @elixir_version "~> 1.17"
  @version "0.1.3"
  @source_url "https://github.com/beam-campus/ex-esdb-commanded-adapter"
  #  @homepage_url "https://github.com/beam-campus/ex-esdb"
  @docs_url "https://hexdocs.pm/ex_esdb_commanded"
  # @package_url "https://hex.pm/packages/ex_esdb"
  # @issues_url "https://github.com/beam-campus/ex-esdb/issues"
  @description "A Commanded Adapter for ExESDB"

  def project do
    [
      app: @app_name,
      version: @version,
      deps: deps(),
      elixir: @elixir_version,
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: erlc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      description: @description,
      docs: docs(),
      package: package(),
      releases: releases(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: coverage_tool()],
      preferred_cli_env: [coveralls: :test]
    ]
  end

  defp releases,
    do: [
      ex_esdb_commanded: [
        include_erts: true,
        include_executables_for: [:unix],
        runtime_config_path: "config/runtime.exs",
        steps: [:assemble, :tar],
        applications: [
          runtime_tools: :permanent,
          logger: :permanent,
          os_mon: :permanent
        ]
      ]
    ]

  # Run "mix help compile.app" to learn about applications.
  def application,
    do: [
      extra_applications:
        [
          :logger,
          :eex,
          :os_mon,
          :runtime_tools,
          :gen_retry
        ] ++ extra_applications(Mix.env())
    ]

  defp extra_applications(:dev),
    do: [
      :wx,
      :observer
    ]

  defp extra_applications(_), do: []

  defp erlc_paths(_),
    do: [
      "src"
    ]

  defp elixirc_paths(:test),
    do: [
      "lib",
      "test/support"
    ]

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:dialyze, "~> 0.2.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:makeup_html, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.37", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:meck, "~> 0.9", only: [:test], runtime: false},
      {:eunit_formatters, "~> 0.5", only: [:test], runtime: false},
      {:mox, "~> 1.0", only: [:test], runtime: false},
      {:jason, "~> 1.4", optional: true},
      {:uuidv7, "~> 1.0"},
      {:elixir_uuid, "~> 1.2"},
      {:commanded, "~> 1.4.8"},
      {:ex_esdb_gater, "~> 0.1.18"}
    ]
  end

  defp coverage_tool do
    # Optional coverage configuration
    {:cover, [output: "_build/cover"]}
  end

  defp docs do
    [
      main: "readme",
      canonical: @docs_url,
      source_ref: "v#{@version}",
      extra_section: "guides",
      extras: [
        "ADR.md",
        "CHANGELOG.md",
        "guides/getting-started.md": [
          filename: "getting-started",
          title: "Getting Started"
        ],
        "guides/event-sourcing-with-cqrs.md": [
          filename: "event-sourcing-with-cqrs",
          title: "Event Sourcing with CQRS"
        ],
        "../README.md": [
          filename: "readme",
          title: "Read Me"
        ]
      ]
    ]
  end

  defp package do
    [
      name: @app_name,
      description: @description,
      version: @version,
      maintainers: ["rgfaber"],
      #      organization: "beam-campus",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      source_url: @source_url
    ]
  end
end
