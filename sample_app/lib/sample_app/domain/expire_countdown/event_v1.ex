defmodule SampleApp.Domain.ExpireCountdown.EventV1 do
  @moduledoc """
  Event emitted when a poll's expiration countdown reaches its end.
  
  This event signals that a poll's countdown has expired and triggers
  downstream processes like automatic poll closure.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :expired_at,
    :version
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    expired_at: DateTime.t(),
    version: integer()
  }
  
  @doc """
  Creates a new CountdownExpired event from a command.
  """
  def from_command(%SampleApp.Domain.ExpireCountdown.CommandV1{} = command) do
    %__MODULE__{
      poll_id: command.poll_id,
      expired_at: command.expired_at,
      version: 1
    }
  end
  
  @doc """
  Gets the event type string for storage.
  """
  def event_type, do: "countdown_expired:v1"
end
