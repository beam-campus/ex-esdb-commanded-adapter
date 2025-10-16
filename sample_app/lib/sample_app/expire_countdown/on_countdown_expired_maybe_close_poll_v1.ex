defmodule SampleApp.ExpireCountdown.OnCountdownExpiredMaybeClosePollV1 do
  use Commanded.ProcessManagers.ProcessManager,
    application: SampleApp.CommandedApp,
    name: "on_countdown_expired_maybe_close_poll_v1"

  alias SampleApp.ExpireCountdown.EventV1, as: CountdownExpired
  alias SampleApp.ClosePoll.CommandV1, as: ClosePoll

  defstruct []

  def interested?(%CountdownExpired{poll_id: poll_id}), do: {:start, poll_id}

  def handle(_, %CountdownExpired{poll_id: poll_id}, _metadata) do
    [
      %ClosePoll{
        poll_id: poll_id,
        reason: "Poll expired",
        closed_by: "system"
      }
    ]
  end

  def after_command(_process_manager, _command), do: :stop
end
