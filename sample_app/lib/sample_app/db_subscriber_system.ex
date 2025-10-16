defmodule SampleApp.DbSubscriberSystem do
  @moduledoc """
  Supervisor for all database event handlers.
  
  Manages the lifecycle of handlers that persist events to the database,
  ensuring they are properly supervised and restarted if necessary.
  """
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [
      # PollSummary handlers
      SampleApp.InitializePoll.InitializedToPollSummaryDBV1,
      SampleApp.CastVote.CastedToPollSummaryDBV1,
      SampleApp.ClosePoll.PollClosedToPollSummaryDBV1,

      # PollResults handlers
      SampleApp.InitializePoll.InitializedToPollResultsDBV1,
      SampleApp.CastVote.CastedToPollResultsDBV1,
      SampleApp.ClosePoll.PollClosedToPollResultsDBV1,

      # VoterHistory handlers
      SampleApp.CastVote.CastedToVoterHistoryDBV1
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
