defmodule SampleApp.Domain.CastVote.CastedToSummaryV1 do
  @moduledoc """
  Projection that handles VoteCasted events and updates the PollSummary read model.
  
  This projection updates vote counts in the poll_summaries cache when votes are cast.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "vote_casted_to_summary_v1",
    subscribe_to: "$et-vote_casted:v1"
  
  alias SampleApp.Domain.CastVote.EventV1, as: VoteCastedEvent
  alias SampleApp.ReadModels.PollSummary
  
  require Logger
  
  def handle(%VoteCastedEvent{} = event, _metadata) do
    Logger.info("🗳️  Updating poll summary with vote for poll: #{event.poll_id}, option: #{event.option_id}")
    
    update_func = fn
      nil -> {nil, nil}
      %PollSummary{} = summary ->
        updated_summary = PollSummary.add_vote(summary, event.option_id)
        {summary, updated_summary}
    end
    
    case Cachex.get_and_update(:poll_summaries, event.poll_id, update_func) do
      {:ok, {_old_value, %PollSummary{} = _updated_summary}} ->
        Logger.info("✅ Poll summary updated successfully for poll: #{event.poll_id}")
        :ok
        
      {:commit, {_old_value, %PollSummary{} = _updated_summary}} ->
        Logger.info("✅ Poll summary updated successfully for poll: #{event.poll_id}")
        :ok
        
      {:ok, {nil, nil}} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:commit, {nil, nil}} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:error, reason} ->
        Logger.error("❌ Failed to update poll summary for poll: #{event.poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
