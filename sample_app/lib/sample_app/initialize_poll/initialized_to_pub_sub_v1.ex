defmodule SampleApp.InitializePoll.InitializedToPubSubV1 do
  @moduledoc """
  Projection that handles PollInitialized events and broadcasts them to PubSub.

  This projection processes poll initialization events and broadcasts them for subscribers
  like cache updaters, UI components, analytics, etc.

  Naming follows the pattern: {event}_to_pubsub_v{version}
  - Event: PollInitialized -> initialized
  - Target: PubSub -> pubsub
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "initialized_to_pubsub_v1",
    subscribe_to: "$et-poll_initialized:v1"

  alias SampleApp.InitializePoll.EventV1, as: PollInitializedEvent

  require Logger

  def handle(%PollInitializedEvent{} = event, _metadata) do
    Logger.info("📊 Processing poll initialization for: #{event.poll_id}")

    # Broadcast the raw event to PubSub
    case Phoenix.PubSub.broadcast(SampleApp.PubSub, "poll_projections", {:poll_initialized, event}) do
      :ok ->
        Logger.info("✅ Poll initialization event broadcasted for: #{event.poll_id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ Failed to broadcast poll initialization for: #{event.poll_id}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
