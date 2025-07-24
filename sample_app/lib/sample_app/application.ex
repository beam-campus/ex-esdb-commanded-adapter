defmodule SampleApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application,
    otp_app: :sample_app

  @impl true
  def start(_type, _args) do
    children = [
      # Start Cachex caches for projections with unique IDs
      Supervisor.child_spec({Cachex, name: :poll_summaries, limit: 10_000}, id: :poll_summaries_cache),
      Supervisor.child_spec({Cachex, name: :poll_results, limit: 10_000}, id: :poll_results_cache),
      Supervisor.child_spec({Cachex, name: :voter_histories, limit: 10_000}, id: :voter_histories_cache),
      # ExESDB.System with explicit OTP app - will use :sample_app config
      {ExESDB.System, :sample_app},
      # Then start the Commanded application
      SampleApp.CommandedApp,
      # Start event handlers (projections) and policies
      SampleApp.Domain.InitializePoll.InitializedToSummaryV1,
      SampleApp.Domain.InitializePoll.InitializedToResultsV1,
      SampleApp.Domain.CastVote.CastedToSummaryV1,
      SampleApp.Domain.CastVote.CastedToResultsV1,
      SampleApp.Domain.CastVote.CastedToVoterHistoryV1,
      SampleApp.Domain.ClosePoll.ClosedToSummaryV1,
      SampleApp.Domain.ExpireCountdown.ExpiredToSummaryV1,
      SampleApp.Domain.StartExpirationCountdown.WhenPollInitializedThenStartExpirationCountdownV1
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SampleApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
