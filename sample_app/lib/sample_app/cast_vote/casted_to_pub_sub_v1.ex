defmodule SampleApp.CastVote.CastedToPubSubV1 do
  @moduledoc """
  Projection that handles VoteCasted events and broadcasts them to PubSub.

  This projection processes vote casting events and broadcasts them for subscribers
  like cache updaters, UI components, analytics, etc.

  Naming follows the pattern: {event}_to_pubsub_v{version}
  - Event: VoteCasted -> casted
  - Target: PubSub -> pubsub
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "casted_to_pubsub_v1",
    subscribe_to: "$et-vote_casted:v1"

  alias SampleApp.CastVote.EventV1, as: VoteCastedEvent

  require Logger

  def handle(%VoteCastedEvent{} = event, _metadata) do
    Logger.info("🗳️  Processing vote cast for poll: #{event.poll_id}")

    # Broadcast the raw event to PubSub

    case Phoenix.PubSub.broadcast(SampleApp.PubSub, "poll_projections", {:vote_casted, event}) do
      :ok ->
        Logger.info("✅ Vote casting event broadcasted for poll: #{event.poll_id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ Failed to broadcast vote casting for: #{event.poll_id}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
