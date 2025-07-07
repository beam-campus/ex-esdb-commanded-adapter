defmodule RegulateGreenhouse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      RegulateGreenhouse.Repo,
      {Ecto.Migrator,
        repos: Application.fetch_env!(:regulate_greenhouse, :ecto_repos),
        skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:regulate_greenhouse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RegulateGreenhouse.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: RegulateGreenhouse.Finch},
      # Start the cache service for read models
      RegulateGreenhouse.CacheService,
      # Start the infrastructure supervisor for reliability components
      RegulateGreenhouse.Infrastructure.Supervisor,
      # Start the Commanded application (without projections)
      RegulateGreenhouse.CommandedApp,
      # Start the event-type-based projection manager
      RegulateGreenhouse.Projections.EventTypeProjectionManager,
      # Start the cache population service for startup cache rebuilding
      RegulateGreenhouse.CachePopulationService
      # Start a worker by calling: RegulateGreenhouse.Worker.start_link(arg)
      # {RegulateGreenhouse.Worker, arg}
    ]

    opts = [strategy: :one_for_one, name: RegulateGreenhouse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") != nil
  end
end
