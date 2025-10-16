defmodule SampleApp.Router do
  @moduledoc """
  Commanded router for the sample app.
  
  This router defines the mapping between commands and aggregates,
  following the vertical slicing architecture patterns.
  """
  use Commanded.Commands.Router

  alias SampleApp.Aggregate
  alias SampleApp.InitializePoll
  alias SampleApp.CastVote
  alias SampleApp.ClosePoll
  alias SampleApp.ExpireCountdown
  alias SampleApp.StartExpirationCountdown

  # Poll commands - routed to Aggregate with wrapper functions
  dispatch([InitializePoll.CommandV1], 
    to: Aggregate, 
    identity: :poll_id,
    function: :execute_initialize_poll)
    
  dispatch([CastVote.CommandV1], 
    to: Aggregate, 
    identity: :poll_id,
    function: :execute_cast_vote)
    
  dispatch([ClosePoll.CommandV1], 
    to: Aggregate, 
    identity: :poll_id,
    function: :execute_close_poll)
    
  dispatch([ExpireCountdown.CommandV1], 
    to: Aggregate, 
    identity: :poll_id,
    function: :execute_expire_countdown)
    
  dispatch([StartExpirationCountdown.CommandV1], 
    to: Aggregate, 
    identity: :poll_id,
    function: :execute_start_expiration_countdown)
end
