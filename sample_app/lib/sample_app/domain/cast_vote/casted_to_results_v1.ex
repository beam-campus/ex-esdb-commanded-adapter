defmodule SampleApp.Domain.CastVote.CastedToResultsV1 do
  @moduledoc """
  Projection that handles VoteCasted events and updates the PollResults read model.
  
  This projection recalculates poll results when votes are cast by getting the 
  updated summary and rebuilding the results from it.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "vote_casted_to_results_v1",
    subscribe_to: "$et-vote_casted:v1"
  
  alias SampleApp.Domain.CastVote.EventV1, as: VoteCastedEvent
  alias SampleApp.ReadModels.{PollSummary, PollResults}
  
  require Logger
  
  def handle(%VoteCastedEvent{} = event, _metadata) do
    Logger.info("📊 Updating poll results with vote for poll: #{event.poll_id}")
    
    # Get the updated summary to rebuild results from
    case Cachex.get(:poll_summaries, event.poll_id) do
      {:ok, %PollSummary{} = summary} ->
        update_results_from_summary(event.poll_id, summary)
        
      {:ok, nil} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:error, reason} ->
        Logger.error("❌ Failed to get poll summary for results update, poll: #{event.poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp update_results_from_summary(poll_id, summary) do
    # We need the poll options to rebuild results, so get them from existing results if available
    case Cachex.get(:poll_results, poll_id) do
      {:ok, %PollResults{results: existing_results}} when existing_results != [] ->
        # Extract options from existing results
        options = extract_options_from_results(existing_results)
        updated_results = PollResults.from_summary(summary, options)
        
        case Cachex.put(:poll_results, poll_id, updated_results) do
          {:ok, true} ->
            Logger.info("✅ Poll results updated successfully for poll: #{poll_id}")
            :ok
            
          {:error, reason} ->
            Logger.error("❌ Failed to update poll results for poll: #{poll_id}, reason: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:ok, _} ->
        Logger.warning("⚠️  Poll results not found or empty for poll: #{poll_id}")
        {:error, :poll_results_not_found}
        
      {:error, reason} ->
        Logger.error("❌ Failed to get poll results for update, poll: #{poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp extract_options_from_results(results) do
    Enum.map(results, fn result ->
      %{id: result.option_id, text: result.option_text}
    end)
  end
end
