defmodule SampleApp.Domain.InitializePoll.InitializedToSummaryV1 do
  @moduledoc """
  Projection that handles PollInitialized events and updates the PollSummary read model.
  
  This projection creates new entries in the poll_summaries cache when polls are initialized.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "poll_initialized_to_summary_v1",
    subscribe_to: "$et-poll_initialized:v1"
  
  alias SampleApp.Domain.InitializePoll.EventV1, as: PollInitializedEvent
  alias SampleApp.ReadModels.PollSummary
  
  require Logger
  
  def handle(%PollInitializedEvent{} = event, _metadata) do
    Logger.info("🏗️  Creating poll summary for poll: #{event.poll_id}")
    
    # Fail-fast: Check if cache is available before attempting operations
    case ensure_cache_available(:poll_summaries) do
      :ok ->
        summary = PollSummary.from_initialization(event)
        
        case Cachex.put(:poll_summaries, event.poll_id, summary) do
          {:ok, true} ->
            Logger.info("✅ Poll summary created successfully for poll: #{event.poll_id}")
            :ok
            
          {:error, reason} ->
            Logger.error("❌ Failed to create poll summary for poll: #{event.poll_id}, reason: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, reason} ->
        Logger.error(
          "❌ Cache :poll_summaries not available for poll: #{event.poll_id}, reason: #{inspect(reason)}"
        )
        {:error, reason}
    end
  end
  
  # Private function to check if cache is available
  defp ensure_cache_available(cache_name) do
    case Process.whereis(cache_name) do
      nil ->
        {:error, :cache_not_available}
      _pid ->
        :ok
    end
  end
end
