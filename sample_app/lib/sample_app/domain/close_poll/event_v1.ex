defmodule SampleApp.Domain.ClosePoll.EventV1 do
  @moduledoc """
  Event emitted when a poll is successfully closed.
  
  This event records the closure and triggers read model updates
  and prevents further voting.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :closed_by,
    :reason,
    :closed_at,
    :version
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    closed_by: String.t(),
    reason: String.t() | nil,
    closed_at: DateTime.t(),
    version: integer()
  }
  
  @doc """
  Creates a new PollClosed event from a command.
  """
  def from_command(%SampleApp.Domain.ClosePoll.CommandV1{} = command) do
    %__MODULE__{
      poll_id: command.poll_id,
      closed_by: command.closed_by,
      reason: command.reason,
      closed_at: command.requested_at,
      version: 1
    }
  end
  
  @doc """
  Gets the event type string for storage.
  """
  def event_type, do: "poll_closed:v1"
end
