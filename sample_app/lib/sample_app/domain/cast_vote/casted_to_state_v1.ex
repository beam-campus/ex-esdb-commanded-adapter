defmodule SampleApp.Domain.CastVote.CastedToStateV1 do
  @moduledoc """
  Event handler that applies VoteCasted events to Poll aggregate state.
  
  This handler updates the Poll aggregate when a vote is cast,
  adding the vote to the votes map.
  """
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.CastVote.EventV1
  
  @doc """
  Applies a VoteCasted event to the Poll aggregate.
  
  Adds the vote to the aggregate's votes map.
  """
  def apply(%Poll{} = poll, %EventV1{} = event) do
    updated_votes = Map.put(poll.votes, event.voter_id, event.option_id)
    
    %Poll{poll | votes: updated_votes}
  end
end
