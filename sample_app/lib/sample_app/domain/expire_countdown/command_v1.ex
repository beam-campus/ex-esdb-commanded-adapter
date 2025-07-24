defmodule SampleApp.Domain.ExpireCountdown.CommandV1 do
  @moduledoc """
  Command to expire a countdown when a poll reaches its expiration time.
  
  This command is typically triggered by an external scheduler or timer
  when a poll's expiration time is reached.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :expired_at
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    expired_at: DateTime.t()
  }
  
  @doc """
  Creates a new ExpireCountdown command.
  """
  def new(attrs) do
    struct(__MODULE__, attrs)
  end
  
  @doc """
  Validates the command according to business rules.
  """
  def valid?(%__MODULE__{} = command) do
    with :ok <- validate_poll_id(command.poll_id),
         :ok <- validate_expired_at(command.expired_at) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Validates the command and raises on error.
  """
  def validate!(%__MODULE__{} = command) do
    case valid?(command) do
      :ok -> command
      {:error, :poll_id_required} -> raise ArgumentError, "poll_id is required"
      {:error, :expired_at_required} -> raise ArgumentError, "expired_at is required"
      {:error, :expired_at_invalid} -> raise ArgumentError, "expired_at must be a DateTime"
    end
  end
  
  defp validate_poll_id(nil), do: {:error, :poll_id_required}
  defp validate_poll_id(""), do: {:error, :poll_id_required}
  defp validate_poll_id(_), do: :ok
  
  defp validate_expired_at(nil), do: {:error, :expired_at_required}
  defp validate_expired_at(%DateTime{}), do: :ok
  defp validate_expired_at(_), do: {:error, :expired_at_invalid}
end
