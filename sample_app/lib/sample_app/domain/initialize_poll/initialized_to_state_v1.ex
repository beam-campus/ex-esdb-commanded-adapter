defmodule SampleApp.Domain.InitializePoll.InitializedToStateV1 do
  @moduledoc """
  Event handler that applies PollInitialized events to Poll aggregate state.
  
  This handler updates the Poll aggregate when a poll is initialized,
  setting all the initial state from the event.
  """
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.InitializePoll.EventV1
  
  @doc """
  Applies a PollInitialized event to the Poll aggregate.
  
  Initializes the aggregate with all poll details from the event.
  """
  def apply(%Poll{} = poll, %EventV1{} = event) do
    %Poll{poll |
      poll_id: event.poll_id,
      title: event.title,
      description: event.description,
      options: event.options,
      created_by: event.created_by,
      expires_at: event.expires_at,
      status: :active,
      votes: %{},
      created_at: event.initialized_at,
      closed_at: nil
    }
  end
end
