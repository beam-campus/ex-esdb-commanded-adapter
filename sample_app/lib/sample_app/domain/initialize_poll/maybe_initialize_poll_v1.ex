defmodule SampleApp.Domain.InitializePoll.MaybeInitializePollV1 do
  @moduledoc """
  Command handler for InitializePoll command.
  
  Business rules:
  - Poll can only be initialized once per poll_id (aggregate must be new)
  - Poll must have at least 2 options
  - Poll must have a title
  - Options cannot be empty strings
  - Expiration date must be in the future (if provided)
  """
  
  alias SampleApp.Aggregates.Poll
  alias SampleApp.Domain.InitializePoll.{CommandV1, EventV1}
  
  @doc """
  Executes the InitializePoll command on a Poll aggregate.
  
  Returns a PollInitialized event if successful, or an error tuple if not.
  """
  def execute(%Poll{poll_id: nil} = _poll, %CommandV1{} = command) do
    case CommandV1.valid?(command) do
      :ok ->
        EventV1.from_command(command)
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  def execute(%Poll{poll_id: poll_id}, %CommandV1{}) when not is_nil(poll_id) do
    {:error, :poll_already_initialized}
  end
end
