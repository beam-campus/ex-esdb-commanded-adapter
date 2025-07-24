defmodule SampleApp.Domain.ExpireCountdown.MaybeExpireCountdownV1 do
  @moduledoc """
  Command handler for ExpireCountdown command.
  
  Business rules:
  - Poll must exist
  - Expiration time must match the poll's expiration time
  - Poll must not already be expired
  """
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.ExpireCountdown.{CommandV1, EventV1}
  
  @doc """
  Executes the ExpireCountdown command on a Poll aggregate.
  
  Returns a CountdownExpired event if successful, or an error tuple if not.
  """
  def execute(%Poll{poll_id: nil}, %CommandV1{}) do
    {:error, :poll_not_found}
  end
  
  def execute(%Poll{} = poll, %CommandV1{} = command) do
    with :ok <- CommandV1.valid?(command),
         :ok <- validate_poll_not_already_expired(poll),
         :ok <- validate_expiration_time_matches(poll, command.expired_at) do
      EventV1.from_command(command)
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_poll_not_already_expired(%Poll{status: :expired}) do
    {:error, :poll_already_expired}
  end
  defp validate_poll_not_already_expired(_poll), do: :ok
  
  defp validate_expiration_time_matches(%Poll{expires_at: poll_expires_at}, command_expired_at) do
    # Allow some tolerance for timing differences (up to 60 seconds)
    case DateTime.compare(poll_expires_at, command_expired_at) do
      :eq -> :ok
      _ ->
        diff = abs(DateTime.diff(poll_expires_at, command_expired_at))
        if diff <= 60 do
          :ok
        else
          {:error, :expiration_time_mismatch}
        end
    end
  end
end
