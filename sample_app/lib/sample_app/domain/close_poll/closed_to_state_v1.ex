defmodule SampleApp.Domain.ClosePoll.ClosedToStateV1 do
  @moduledoc """
  Event handler that applies PollClosed events to Poll aggregate state.
  
  This handler updates the Poll aggregate when a poll is closed,
  setting the status to closed and the closed_at timestamp.
  """
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.ClosePoll.EventV1
  
  @doc """
  Applies a PollClosed event to the Poll aggregate.
  
  Sets the poll status to closed and records the closure timestamp.
  """
  def apply(%Poll{} = poll, %EventV1{} = event) do
    %Poll{poll |
      status: :closed,
      closed_at: event.closed_at
    }
  end
end
