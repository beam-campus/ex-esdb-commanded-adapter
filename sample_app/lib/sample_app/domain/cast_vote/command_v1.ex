defmodule SampleApp.Domain.CastVote.CommandV1 do
  @moduledoc """
  Command to cast a vote on a poll option.
  
  This command is triggered when a user wants to vote on a specific
  option in an active poll.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :option_id,
    :voter_id,
    :requested_at
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    option_id: String.t(),
    voter_id: String.t(),
    requested_at: DateTime.t()
  }
  
  @doc """
  Creates a new CastVote command.
  """
  def new(attrs) do
    struct(__MODULE__, attrs)
  end
  
  @doc """
  Validates the command according to business rules.
  """
  def valid?(%__MODULE__{} = command) do
    with :ok <- validate_poll_id(command.poll_id),
         :ok <- validate_option_id(command.option_id),
         :ok <- validate_voter_id(command.voter_id) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_poll_id(nil), do: {:error, :poll_id_required}
  defp validate_poll_id(""), do: {:error, :poll_id_required}
  defp validate_poll_id(_), do: :ok
  
  defp validate_option_id(nil), do: {:error, :option_id_required}
  defp validate_option_id(""), do: {:error, :option_id_required}
  defp validate_option_id(_), do: :ok
  
  defp validate_voter_id(nil), do: {:error, :voter_id_required}
  defp validate_voter_id(""), do: {:error, :voter_id_required}
  defp validate_voter_id(_), do: :ok
end
