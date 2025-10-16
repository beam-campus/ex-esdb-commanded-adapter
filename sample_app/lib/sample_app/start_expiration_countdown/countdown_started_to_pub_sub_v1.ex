defmodule SampleApp.StartExpirationCountdown.CountdownStartedToPubSubV1 do
  @moduledoc """
  Projection that handles CountdownStarted events and broadcasts them to PubSub.

  This projection processes countdown start events and broadcasts them for subscribers
  like cache updaters, UI components, analytics, etc.

  Naming follows the pattern: {event}_to_pubsub_v{version}
  - Event: CountdownStarted -> countdown_started
  - Target: PubSub -> pubsub
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "countdown_started_to_pubsub_v1",
    subscribe_to: "$et-countdown_started:v1"

  alias SampleApp.StartExpirationCountdown.EventV1, as: CountdownStartedEvent

  require Logger

  def handle(%CountdownStartedEvent{} = event, _metadata) do
    Logger.info("⏰ Processing countdown start for poll: #{event.poll_id}")

    # Broadcast the raw event to PubSub
    case Phoenix.PubSub.broadcast(SampleApp.PubSub, "poll_projections", {:countdown_started, event}) do
      :ok ->
        Logger.info("✅ Countdown start event broadcasted for poll: #{event.poll_id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ Failed to broadcast countdown start for: #{event.poll_id}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
