defmodule SampleApp.PubSubProjectionsSystem do
  @moduledoc false
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      SampleApp.CastVote.CastedToPubSubV1,
      SampleApp.ExpireCountdown.CountdownExpiredToPubSubV1,
      SampleApp.InitializePoll.InitializedToPubSubV1,
      SampleApp.StartExpirationCountdown.CountdownStartedToPubSubV1,
      SampleApp.ClosePoll.PollClosedToPubSubV1
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
