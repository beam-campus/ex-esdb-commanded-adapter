defmodule SampleApp.Domain.StartExpirationCountdown.WhenPollInitializedThenStartExpirationCountdownV1 do
  @moduledoc """
  Policy that triggers expiration countdown start when a poll with expiration is initialized.
  
  This policy listens to PollInitialized events and automatically dispatches a 
  StartExpirationCountdown command if the poll has an expiration time.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "poll_initialized_start_countdown_policy_v1",
    subscribe_to: "$et-poll_initialized:v1"
  
  alias SampleApp.Domain.InitializePoll.EventV1, as: PollInitialized
  alias SampleApp.Domain.StartExpirationCountdown.CommandV1, as: StartExpirationCountdownCommand
  alias SampleApp.CommandedApp
  
  require Logger
  
  def handle(%PollInitialized{expires_at: nil} = _event, _metadata) do
    # Poll has no expiration, no need to start countdown
    :ok
  end
  
  def handle(%PollInitialized{expires_at: expires_at} = event, _metadata) when not is_nil(expires_at) do
    Logger.info("Starting expiration countdown for poll #{event.poll_id} expiring at #{expires_at}")
    
    command = %StartExpirationCountdownCommand{
      poll_id: event.poll_id,
      expires_at: event.expires_at,
      started_at: DateTime.utc_now()
    }
    
    # Dispatch through CommandedApp as required by guidelines
    case CommandedApp.dispatch(command) do
      :ok -> 
        Logger.info("Successfully started expiration countdown for poll #{event.poll_id}")
        :ok
      
      {:error, reason} -> 
        Logger.error("Failed to start expiration countdown for poll #{event.poll_id}: #{inspect(reason)}")
        # In a real system, you might want to handle this error more gracefully
        # For now, we'll let it continue
        :ok
    end
  end
end
