defmodule SampleApp.InitializePoll.InitializedToPollResultsCacheV1 do
  @moduledoc """
  Cache subscriber that listens to poll initialization events and updates the poll results cache.

  This subscriber follows the vertical slicing architecture and focuses on updating
  the poll results cache when polls are initialized.
  """

  use GenServer

  alias SampleApp.ReadModels.PollResults

  require Logger

  @cache_name :poll_results
  @projections_topic "poll_projections"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("📊 Starting poll results cache subscriber for initialization events")

    # Subscribe to projection events
    Phoenix.PubSub.subscribe(SampleApp.PubSub, @projections_topic)

    {:ok, %{}}
  end

  defp result_from_option(option),
    do: %{
      option_id: option.id,
      option_text: option.text,
      vote_count: 0,
      percentage: 0.0,
      rank: 1
    }

  # Handle poll initialization
  def handle_info({:poll_initialized, event}, state) do
    Logger.info("📊 Initializing poll results cache for: #{event.poll_id}")

    # Create initial results structure
    initial_results = %PollResults{
      poll_id: event.poll_id,
      results:
        event.options
        |> Enum.map(&result_from_option/1),
      total_votes: 0,
      created_at: event.initialized_at
    }

    case Cachex.put(@cache_name, event.poll_id, initial_results) do
      {:ok, true} ->
        Logger.info("✅ Poll results cache initialized for: #{event.poll_id}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("❌ Failed to initialize poll results cache: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Ignore other messages
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
