defmodule SampleApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application,
    otp_app: :sample_app

  @impl true
  def start(_type, _args) do
    children = [
      # Start Ecto repository
      SampleApp.Repo,
      {Phoenix.PubSub, name: SampleApp.PubSub},
      SampleApp.CachesSystem,
      # ExESDB.System with explicit OTP app - will use :sample_app config
      {ExESDB.System, :sample_app},
      # Then start the Commanded application
      SampleApp.CommandedApp,
      # Start event handlers (projections) and policies
      # PubSub projections
      SampleApp.PubSubProjectionsSystem,
      SampleApp.CastVote.CastedToPubSubV1,
      # Cache subscriber system to manage all cache subscribers
      SampleApp.ReadModels.CacheSubscriberSystem,
      # Policy handlers
      SampleApp.PolicySystem,

      # Database subscriber system
      SampleApp.DbSubscriberSystem,

      # Cache recovery system
      SampleApp.CacheRecovery.Supervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SampleApp.Supervisor]
    Supervisor.start_link(children, opts)
    |> then(&init_cache_recovery/1)
  end

  defp init_cache_recovery({:ok, _pid} = result) do
    SampleApp.CacheRecovery.Supervisor.register_default_caches()
    SampleApp.CacheRecovery.Supervisor.recover_all()
    result
  end

  defp init_cache_recovery(error), do: error
end
