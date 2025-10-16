defmodule SampleApp.InitializePoll.InitializedToPollSummaryCacheV1 do
  @moduledoc """
  Cache subscriber that listens to poll initialization events and updates the poll summary cache.

  This subscriber follows the vertical slicing architecture and focuses on updating
  the poll summary cache when polls are initialized.
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
    Logger.info("📊 Starting poll summary cache subscriber for initialization events")

    # Subscribe to projection events
    Phoenix.PubSub.subscribe(SampleApp.PubSub, @projections_topic)

    {:ok, %{}}
  end

  # Handle poll initialization
  def handle_info({:poll_initialized, event}, state) do
    Logger.info("📊 Updating poll summary cache for initialized poll: #{event.poll_id}")

    # Create cache entry
    poll_summary = %PollSummary{
      poll_id: event.poll_id,
      title: event.title,
      description: event.description,
      status: :active,
      created_at: event.initialized_at
    }

    case Cachex.put(@cache_name, event.poll_id, poll_summary) do
      {:ok, true} ->
        Logger.info("✅ Poll summary cache updated for: #{event.poll_id}")
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
