defmodule SampleApp.Domain.ClosePoll.CommandV1 do
  @moduledoc """
  Command to manually close a poll before its expiration time.
  
  This command allows poll creators to close their polls early,
  preventing further voting.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :closed_by,
    :reason,
    :requested_at
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    closed_by: String.t(),
    reason: String.t() | nil,
    requested_at: DateTime.t()
  }
  
  @doc """
  Creates a new ClosePoll command.
  """
  def new(attrs) do
    struct(__MODULE__, attrs)
  end
  
  @doc """
  Validates the command according to business rules.
  """
  def valid?(%__MODULE__{} = command) do
    with :ok <- validate_poll_id(command.poll_id),
         :ok <- validate_closed_by(command.closed_by) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_poll_id(nil), do: {:error, :poll_id_required}
  defp validate_poll_id(""), do: {:error, :poll_id_required}
  defp validate_poll_id(_), do: :ok
  
  defp validate_closed_by(nil), do: {:error, :closed_by_required}
  defp validate_closed_by(""), do: {:error, :closed_by_required}
  defp validate_closed_by(_), do: :ok
end
