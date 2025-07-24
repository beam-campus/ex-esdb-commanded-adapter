defmodule SampleApp.Domain.CastVote.EventV1 do
  @moduledoc """
  Event emitted when a vote is successfully cast on a poll.
  
  This event records the vote and triggers read model updates
  and other domain reactions.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :option_id,
    :voter_id,
    :voted_at,
    :version
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    option_id: String.t(),
    voter_id: String.t(),
    voted_at: DateTime.t(),
    version: integer()
  }
  
  @doc """
  Creates a new VoteCasted event from a command.
  """
  def from_command(%SampleApp.Domain.CastVote.CommandV1{} = command) do
    %__MODULE__{
      poll_id: command.poll_id,
      option_id: command.option_id,
      voter_id: command.voter_id,
      voted_at: command.requested_at,
      version: 1
    }
  end
  
  @doc """
  Gets the event type string for storage.
  """
  def event_type, do: "vote_casted:v1"
end
