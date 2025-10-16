defmodule SampleApp.CastVote.CastedToPollSummaryCacheV1 do
  @moduledoc """
  Cache subscriber that listens to vote casting events and updates the poll summary cache.

  This subscriber follows the vertical slicing architecture and focuses on updating
  the poll summary cache when votes are cast, specifically handling:
  - Total vote count updates
  - Per-option vote count updates
  """

  use GenServer

  alias SampleApp.ReadModels.PollSummary

  require Logger

  @cache_name :poll_summaries
  @projections_topic "poll_projections"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("📊 Starting poll summary cache subscriber for vote casting events")

    # Subscribe to projection events
    Phoenix.PubSub.subscribe(SampleApp.PubSub, @projections_topic)

    {:ok, %{}}
  end

  # Handle messages
  def handle_info({:vote_casted, event}, state) do
    Logger.info("📊 Updating poll summary cache for new vote in poll: #{event.poll_id}")

    update_cache(event)
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private functions
  defp update_cache(event) do
    case Cachex.get_and_update(@cache_name, event.poll_id, fn
      nil ->
        Logger.warning("⚠️ No existing poll summary found for: #{event.poll_id}", %{poll_id: event.poll_id})
        {nil, nil}

      existing ->
        updated = %PollSummary{existing |
          total_votes: existing.total_votes + 1,
          vote_counts: Map.update(
            existing.vote_counts,
            event.option_id,
            1,
            &(&1 + 1)
          )
        }
        {updated, updated}
    end) do
      {:ok, nil} ->
        Logger.warning("⚠️ No poll summary found for: #{event.poll_id}", %{poll_id: event.poll_id})

      {:ok, updated} ->
        Logger.info("✅ Poll summary updated for: #{event.poll_id}")
        {:ok, updated}

      {:error, reason} ->
        Logger.error("❌ Failed to update poll summary: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
