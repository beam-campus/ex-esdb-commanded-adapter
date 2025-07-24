defmodule SampleApp.Domain.ClosePoll.MaybeClosePollV1 do
  @moduledoc """
  Command handler for ClosePoll command.
  
  Business rules:
  - Poll must exist and be active
  - Only the poll creator can close the poll manually
  - Cannot close an already closed poll
  """
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.ClosePoll.{CommandV1, EventV1}
  
  @doc """
  Executes the ClosePoll command on a Poll aggregate.
  
  Returns a PollClosed event if successful, or an error tuple if not.
  """
  def execute(%Poll{poll_id: nil}, %CommandV1{}) do
    {:error, :poll_not_found}
  end
  
  def execute(%Poll{} = poll, %CommandV1{} = command) do
    with :ok <- CommandV1.valid?(command),
         :ok <- validate_poll_active(poll),
         :ok <- validate_creator_permission(poll, command.closed_by) do
      EventV1.from_command(command)
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_poll_active(%Poll{status: :active}), do: :ok
  defp validate_poll_active(%Poll{status: :closed}), do: {:error, :poll_already_closed}
  defp validate_poll_active(%Poll{status: :expired}), do: {:error, :poll_expired}
  defp validate_poll_active(_), do: {:error, :poll_not_active}
  
  defp validate_creator_permission(%Poll{} = poll, closed_by) do
    if Poll.created_by?(poll, closed_by) do
      :ok
    else
      {:error, :not_poll_creator}
    end
  end
end
