defmodule SampleApp.ClosePoll.PollClosedToPubSubV1 do
  @moduledoc """
  Projection that handles PollClosed events and broadcasts them to PubSub.

  This projection processes poll closure events and broadcasts them for subscribers
  like cache updaters, UI components, analytics, etc.

  Naming follows the pattern: {event}_to_pubsub_v{version}
  - Event: PollClosed -> poll_closed
  - Target: PubSub -> pubsub
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "poll_closed_to_pubsub_v1",
    subscribe_to: "$et-poll_closed:v1"

  alias SampleApp.ClosePoll.EventV1, as: PollClosedEvent

  require Logger

  def handle(%PollClosedEvent{} = event, _metadata) do
    Logger.info("🔒 Processing poll closure for: #{event.poll_id}")

    # Broadcast the raw event to PubSub
    case Phoenix.PubSub.broadcast(SampleApp.PubSub, "poll_projections", {:poll_closed, event}) do
      :ok ->
        Logger.info("✅ Poll closure event broadcasted for: #{event.poll_id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ Failed to broadcast poll closure for: #{event.poll_id}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
