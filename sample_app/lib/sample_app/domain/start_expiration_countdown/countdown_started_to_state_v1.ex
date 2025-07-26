defmodule SampleApp.Domain.StartExpirationCountdown.CountdownStartedToStateV1 do
  @moduledoc """
  Event handler that applies ExpirationCountdownStarted events to Poll aggregate state.
  
  This handler updates the Poll aggregate when expiration countdown is started.
  For now, this doesn't change the aggregate state significantly, but could be
  enhanced to track countdown status.
  """
  
  alias SampleApp.Aggregates.Poll
  alias SampleApp.Domain.StartExpirationCountdown.EventV1
  
  @doc """
  Applies an ExpirationCountdownStarted event to the Poll aggregate.
  
  Currently a no-op since the expiration tracking is mainly for external processes.
  In a more complex system, this might set a countdown_started flag.
  """
  def apply(%Poll{} = poll, %EventV1{} = _event) do
    # For now, we don't modify the aggregate state
    # In a real system, you might add a countdown_started field
    poll
  end
end
