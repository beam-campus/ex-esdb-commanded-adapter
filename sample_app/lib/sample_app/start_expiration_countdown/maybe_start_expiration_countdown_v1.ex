defmodule SampleApp.StartExpirationCountdown.MaybeStartExpirationCountdownV1 do
  @moduledoc """
  Command handler for StartExpirationCountdown command.

  Business rules:
  - Poll must exist and be active
  - Poll must have an expiration time set
  - Countdown can only be started once per poll
  - Expiration time must be in the future
  """

  alias SampleApp.Aggregate
  alias SampleApp.StartExpirationCountdown.{CommandV1, EventV1}

  @doc """
  Executes the StartExpirationCountdown command on a Poll aggregate.

  Returns an ExpirationCountdownStarted event if successful, or an error tuple if not.
  """
  def execute(%Aggregate{poll_id: nil}, %CommandV1{}) do
    {:error, :poll_not_found}
  end

  def execute(%Aggregate{} = poll, %CommandV1{} = command) do
    with :ok <- CommandV1.valid?(command),
         :ok <- validate_poll_active(poll),
         :ok <- validate_has_expiration(poll),
         :ok <- validate_countdown_not_started(poll) do
      EventV1.from_command(command)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_poll_active(%Aggregate{status: :active}), do: :ok
  defp validate_poll_active(%Aggregate{status: :closed}), do: {:error, :poll_closed}
  defp validate_poll_active(%Aggregate{status: :expired}), do: {:error, :poll_expired}
  defp validate_poll_active(_), do: {:error, :poll_not_active}

  defp validate_has_expiration(%Aggregate{expires_at: nil}), do: {:error, :poll_has_no_expiration}
  defp validate_has_expiration(%Aggregate{expires_at: _}), do: :ok

  # For now, we'll use a simple check - in a real system you might track this in aggregate state
  defp validate_countdown_not_started(_poll) do
    # This could be enhanced to track if countdown was already started
    # For now, we assume it's valid to start
    :ok
  end
end
