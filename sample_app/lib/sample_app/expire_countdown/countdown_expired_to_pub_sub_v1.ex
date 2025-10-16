defmodule SampleApp.ExpireCountdown.CountdownExpiredToPubSubV1 do
  @moduledoc """
  Projection that handles CountdownExpired events and broadcasts them to PubSub.

  This projection processes countdown expiration events and broadcasts them for subscribers
  like cache updaters, UI components, analytics, etc.

  Naming follows the pattern: {event}_to_pubsub_v{version}
  - Event: CountdownExpired -> countdown_expired
  - Target: PubSub -> pubsub
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "countdown_expired_to_pubsub_v1",
    subscribe_to: "$et-countdown_expired:v1"

  alias SampleApp.ExpireCountdown.EventV1, as: CountdownExpiredEvent

  require Logger

  def handle(%CountdownExpiredEvent{} = event, _metadata) do
    Logger.info("⌛ Processing countdown expiration for poll: #{event.poll_id}")

    # Broadcast the raw event to PubSub
    case Phoenix.PubSub.broadcast(SampleApp.PubSub, "poll_projections", {:countdown_expired, event}) do
      :ok ->
        Logger.info("✅ Countdown expiration event broadcasted for poll: #{event.poll_id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ Failed to broadcast countdown expiration for: #{event.poll_id}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
