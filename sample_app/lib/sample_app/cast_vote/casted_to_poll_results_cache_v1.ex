defmodule SampleApp.CastVote.CastedToPollResultsCacheV1 do
  @moduledoc """
  Subscriber that listens to vote casting PubSub events and updates the poll results cache.

  This subscriber updates the poll results cache following the vertical slicing architecture.

  Naming follows the pattern: {event}_to_{readmodel}_cache_v{version}
  - Event: VoteCasted -> casted
  - Target: Poll results cache -> poll_results_cache
  """

  use GenServer

  alias SampleApp.ReadModels.PollResults

  require Logger

  @cache_name :poll_results
  @projections_topic "poll_projections"
  @cache_updates_topic "poll_results_cache_updates"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("🗄️  Starting vote casting cache subscriber")

    # Subscribe to projection events
    Phoenix.PubSub.subscribe(SampleApp.PubSub, @projections_topic)

    {:ok, %{}}
  end

  # Handle vote casting
  def handle_info({:vote_casted, event}, state) do
    case Cachex.get(@cache_name, event.poll_id) do
      {:ok, nil} ->
        Logger.warning("⚠️ No poll results found for: #{event.poll_id}", %{poll_id: event.poll_id})
        {:noreply, state}

      {:ok, poll_results} ->
        updated = PollResults.add_vote(poll_results, event.option_id)
        case Cachex.put(@cache_name, event.poll_id, updated) do
          {:ok, true} ->
            Logger.info("✅ Poll results updated for: #{event.poll_id}")
            broadcast_cache_update(:updated, updated)
            {:noreply, state}
          {:error, reason} ->
            Logger.error("❌ Failed to update poll results: #{inspect(reason)}")
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to fetch poll results: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Ignore other messages
  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Broadcast cache update
  defp broadcast_cache_update(operation, read_model) do
    message = case operation do
      :created -> {:poll_results_created, read_model}
      :updated -> {:poll_results_updated, read_model}
    end

    case Phoenix.PubSub.broadcast(SampleApp.PubSub, @cache_updates_topic, message) do
      :ok ->
        Logger.debug("📡 Cache update broadcasted for poll: #{read_model.poll_id}")

      {:error, reason} ->
        Logger.warning("📡 Failed to broadcast cache update: #{inspect(reason)}")
        # Don't fail the cache operation for broadcast failures
    end
  end
end
