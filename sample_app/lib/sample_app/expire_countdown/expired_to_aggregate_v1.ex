defmodule SampleApp.ExpireCountdown.ExpiredToAggregateV1 do
  @moduledoc """
  Handles the CountdownExpired event and applies state changes to the Poll aggregate.

  This event handler marks the poll as expired in the aggregate state.
  """

  alias SampleApp.ExpireCountdown.EventV1
  alias SampleApp.Aggregate

  @spec apply(Aggregate.t(), EventV1.t()) :: Aggregate.t()
  def apply(%Aggregate{} = poll, %EventV1{} = event) do
    # Update the poll to reflect that its countdown has expired
    %Aggregate{
      poll
      | status: :expired,
        expired_at: event.expired_at
    }
  end
end
