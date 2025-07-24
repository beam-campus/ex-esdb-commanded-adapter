defmodule SampleApp.Domain.ClosePoll.ClosedToSummaryV1 do
  @moduledoc """
  Projection that handles PollClosed events and updates the PollSummary read model.
  
  This projection marks polls as closed in the poll_summaries cache when they are manually closed.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "poll_closed_to_summary_v1",
    subscribe_to: "$et-poll_closed:v1"
  
  alias SampleApp.Domain.ClosePoll.EventV1, as: PollClosedEvent
  alias SampleApp.ReadModels.PollSummary
  
  require Logger
  
  def handle(%PollClosedEvent{} = event, _metadata) do
    Logger.info("🔒 Marking poll as closed in summary for poll: #{event.poll_id}")
    
    update_func = fn
      nil -> {nil, nil}
      %PollSummary{} = summary ->
        updated_summary = PollSummary.close(summary, event.closed_at)
        {summary, updated_summary}
    end
    
    case Cachex.get_and_update(:poll_summaries, event.poll_id, update_func) do
      {:ok, {_old_value, %PollSummary{} = _updated_summary}} ->
        Logger.info("✅ Poll summary marked as closed successfully for poll: #{event.poll_id}")
        :ok
        
      {:commit, {_old_value, %PollSummary{} = _updated_summary}} ->
        Logger.info("✅ Poll summary marked as closed successfully for poll: #{event.poll_id}")
        :ok
        
      {:ok, {nil, nil}} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:commit, {nil, nil}} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:error, reason} ->
        Logger.error("❌ Failed to close poll summary for poll: #{event.poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
end
