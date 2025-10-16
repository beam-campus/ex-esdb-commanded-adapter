defmodule SampleApp.CastVote.CastedToVoterHistoryCacheV1 do
  @moduledoc """
  Cache subscriber that listens to vote casting events and updates the voter history cache.

  This subscriber follows the vertical slicing architecture and focuses on updating
  the voter history cache when votes are cast.
  """

  use GenServer

  alias SampleApp.ReadModels.VoterHistory
  alias SampleApp.CastVote.EventV1, as: VoteCastedEvent

  require Logger

  @cache_name :voter_histories
  @projections_topic "poll_projections"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("🗳️ Starting voter history cache subscriber for vote casting events")

    # Subscribe to projection events
    Phoenix.PubSub.subscribe(SampleApp.PubSub, @projections_topic)

    {:ok, %{}}
  end

  # Handle messages
  def handle_info({:vote_casted, %VoteCastedEvent{} = event}, state) do
    Logger.info("🗳️ Updating voter history cache for vote cast by: #{event.voter_id}")

    # Add or update vote in history
    update_cache(event)
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private functions
  defp update_cache(event) do
    case Cachex.get_and_update(@cache_name, event.voter_id, fn
      nil ->
        history = VoterHistory.new(event.voter_id)
        {history, VoterHistory.add_vote(history, event.poll_id, event.option_id, event.voted_at)}

      existing ->
        updated = VoterHistory.add_vote(existing, event.poll_id, event.option_id, event.voted_at)
        {updated, updated}
    end) do
      {:ok, updated} ->
        Logger.info("✅ Voter history updated for: #{event.voter_id}")
        {:ok, updated}

      {:error, reason} ->
        Logger.error("❌ Failed to update voter history: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
