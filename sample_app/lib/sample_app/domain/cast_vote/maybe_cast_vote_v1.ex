defmodule SampleApp.Domain.CastVote.MaybeCastVoteV1 do
  @moduledoc """
  Command handler for CastVote command.
  
  Business rules:
  - Poll must exist and be active
  - Poll must not be expired
  - User can only vote once per poll
  - Option must exist in the poll
  - Voter ID must be provided
  """
  
  alias SampleApp.Aggregates.Poll
  alias SampleApp.Domain.CastVote.{CommandV1, EventV1}
  
  @doc """
  Executes the CastVote command on a Poll aggregate.
  
  Returns a VoteCasted event if successful, or an error tuple if not.
  """
  def execute(%Poll{poll_id: nil}, %CommandV1{}) do
    {:error, :poll_not_found}
  end
  
  def execute(%Poll{} = poll, %CommandV1{} = command) do
    with :ok <- CommandV1.valid?(command),
         :ok <- validate_poll_active(poll),
         :ok <- validate_not_expired(poll),
         :ok <- validate_option_exists(poll, command.option_id),
         :ok <- validate_voter_not_voted(poll, command.voter_id) do
      EventV1.from_command(command)
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_poll_active(%Poll{status: :active}), do: :ok
  defp validate_poll_active(%Poll{status: :closed}), do: {:error, :poll_closed}
  defp validate_poll_active(%Poll{status: :expired}), do: {:error, :poll_expired}
  defp validate_poll_active(_), do: {:error, :poll_not_active}
  
  defp validate_not_expired(%Poll{} = poll) do
    if Poll.expired?(poll) do
      {:error, :poll_expired}
    else
      :ok
    end
  end
  
  defp validate_option_exists(%Poll{} = poll, option_id) do
    if Poll.option_exists?(poll, option_id) do
      :ok
    else
      {:error, :invalid_option}
    end
  end
  
  defp validate_voter_not_voted(%Poll{} = poll, voter_id) do
    if Poll.voter_has_voted?(poll, voter_id) do
      {:error, :voter_already_voted}
    else
      :ok
    end
  end
end
