defmodule SampleApp.Domain.StartExpirationCountdown.EventV1 do
  @moduledoc """
  Event emitted when an expiration countdown is started for a poll.
  
  This event indicates that the poll now has an active expiration countdown
  and can trigger automatic expiration processes.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :expires_at,
    :started_at,
    :version
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    expires_at: DateTime.t(),
    started_at: DateTime.t(),
    version: integer()
  }
  
  @doc """
  Creates a new ExpirationCountdownStarted event from a command.
  """
  def from_command(%SampleApp.Domain.StartExpirationCountdown.CommandV1{} = command) do
    %__MODULE__{
      poll_id: command.poll_id,
      expires_at: command.expires_at,
      started_at: command.started_at,
      version: 1
    }
  end
  
  @doc """
  Gets the event type string for storage.
  """
  def event_type, do: "expiration_countdown_started:v1"
end
