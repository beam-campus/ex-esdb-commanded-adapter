defmodule SampleApp.ClosePoll.PollClosedToPollSummaryCacheV1 do
  @moduledoc """
  Cache subscriber that listens to poll closure events and updates the poll summary cache.

  This subscriber follows the vertical slicing architecture and focuses on updating
  the poll summary cache when polls are closed.
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
    Logger.info("🔒 Starting poll summary cache subscriber for closure events")

    # Subscribe to projection events
    Phoenix.PubSub.subscribe(SampleApp.PubSub, @projections_topic)

    {:ok, %{}}
  end

  # Handle poll closure
  def handle_info({:poll_closed, event}, state) do
    Logger.info("🔒 Updating poll summary cache for closed poll: #{event.poll_id}")

    case Cachex.get_and_update(@cache_name, event.poll_id, fn
           # Don't create if doesn't exist
           nil ->
             {nil, nil}

           existing ->
             updated = %PollSummary{existing | status: :closed, closed_at: event.closed_at}
             {existing, updated}
         end) do
      {:ok, nil} ->
        Logger.warning("⚠️ No existing poll summary found for: #{event.poll_id}", %{poll_id: event.poll_id})
        {:noreply, state}

      {:ok, _updated} ->
        Logger.info("✅ Poll summary cache updated for closed poll: #{event.poll_id}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("❌ Failed to update poll summary cache: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Ignore other messages
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
