defmodule SampleApp.Domain.StartExpirationCountdown.CommandV1 do
  @moduledoc """
  Command to start the expiration countdown for polls with an expiration time.
  
  This command is typically triggered automatically by a policy when a poll
  is initialized with an expiration time.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :expires_at,
    :started_at
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    expires_at: DateTime.t(),
    started_at: DateTime.t()
  }
  
  @doc """
  Creates a new StartExpirationCountdown command.
  """
  def new(attrs) do
    struct(__MODULE__, attrs)
  end
  
  @doc """
  Validates the command according to business rules.
  """
  def valid?(%__MODULE__{} = command) do
    with :ok <- validate_poll_id(command.poll_id),
         :ok <- validate_expires_at(command.expires_at) do
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
      {:error, :expires_at_required} -> raise ArgumentError, "expires_at is required"
      {:error, :expiration_must_be_future} -> raise ArgumentError, "expiration must be in the future"
    end
  end
  
  defp validate_poll_id(nil), do: {:error, :poll_id_required}
  defp validate_poll_id(""), do: {:error, :poll_id_required}
  defp validate_poll_id(_), do: :ok
  
  defp validate_expires_at(nil), do: {:error, :expires_at_required}
  defp validate_expires_at(expires_at) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :expiration_must_be_future}
    end
  end
end
