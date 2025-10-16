defmodule SampleApp.InitializePoll.OnPollInitializedMaybeStartCountdownV1 do
  @moduledoc """
  Policy that triggers expiration countdown start when a poll with expiration is initialized.

  This policy listens to PollInitialized events and automatically dispatches a 
  StartExpirationCountdown command if the poll has an expiration time.
  """

  use Commanded.ProcessManagers.ProcessManager,
    application: SampleApp.CommandedApp,
    name: "on_poll_initialized_maybe_start_countdown_v1"

  defstruct []

  alias SampleApp.InitializePoll.EventV1, as: PollInitialized
  alias SampleApp.StartExpirationCountdown.CommandV1, as: StartExpirationCountdownCommand

  require Logger

  def interested?(%PollInitialized{expires_at: nil}), do: false
  def interested?(%PollInitialized{poll_id: poll_id}), do: {:start, poll_id}

  def handle(%__MODULE__{}, %PollInitialized{expires_at: expires_at} = event, _metadata)
      when not is_nil(expires_at) do
    Logger.info(
      "Starting expiration countdown for poll #{event.poll_id} expiring at #{expires_at}"
    )

    command = %StartExpirationCountdownCommand{
      poll_id: event.poll_id,
      expires_at: event.expires_at,
      started_at: DateTime.utc_now()
    }

    command
  end

  def apply(%__MODULE__{} = process_manager, %PollInitialized{}), do: process_manager

  def error({:error, reason}, _command, _failure_context) do
    Logger.error("Failed to start expiration countdown: #{inspect(reason)}")

    # Skip the failed command but allow process to continue
    {:skip, :continue_pending}
  end
end
