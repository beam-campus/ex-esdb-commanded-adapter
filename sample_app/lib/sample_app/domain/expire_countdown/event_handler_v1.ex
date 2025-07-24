defmodule SampleApp.Domain.ExpireCountdown.EventHandlerV1 do
  @moduledoc """
  Handles the CountdownExpired event and applies state changes to the Poll aggregate.
  
  This event handler marks the poll as expired in the aggregate state.
  """
  
  alias SampleApp.Domain.ExpireCountdown.EventV1
  alias SampleApp.Shared.Poll
  
  @spec apply(Poll.t(), EventV1.t()) :: Poll.t()
  def apply(%Poll{} = poll, %EventV1{} = event) do
    # Update the poll to reflect that its countdown has expired
    %Poll{
      poll
      | status: :expired,
        expired_at: event.expired_at
    }
  end
end
