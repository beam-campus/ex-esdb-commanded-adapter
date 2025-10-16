defmodule SampleApp.PolicySystem do
  @moduledoc """
  Supervisor for all policy process managers in the SampleApp domain.

  Manages the lifecycle of policy process managers that listen to events
  and trigger follow-up commands based on business rules.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Policy process managers
      SampleApp.InitializePoll.OnPollInitializedMaybeStartCountdownV1,
      SampleApp.StartExpirationCountdown.OnCountdownStartedMaybeExpireV1,
      SampleApp.ExpireCountdown.OnCountdownExpiredMaybeClosePollV1
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
