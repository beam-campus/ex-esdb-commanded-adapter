defmodule SampleApp.Domain.ExpireCountdown.ExpiredToSummaryV1 do
  @moduledoc """
  Projection that handles CountdownExpired events and updates the PollSummary read model.
  
  This projection marks polls as expired in the poll_summaries cache when their countdown expires.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "countdown_expired_to_summary_v1",
    subscribe_to: "$et-countdown_expired:v1"
  
  alias SampleApp.Domain.ExpireCountdown.EventV1, as: CountdownExpiredEvent
  alias SampleApp.ReadModels.PollSummary
  
  require Logger
  
  def handle(%CountdownExpiredEvent{} = event, _metadata) do
    Logger.info("⏰ Marking poll as expired in summary for poll: #{event.poll_id}")
    
    update_func = fn
      nil -> {nil, nil}
      %PollSummary{} = summary ->
        updated_summary = PollSummary.expire(summary, event.expired_at)
        {summary, updated_summary}
    end
    
    case Cachex.get_and_update(:poll_summaries, event.poll_id, update_func) do
      {:ok, {_old_value, %PollSummary{} = _updated_summary}} ->
        Logger.info("✅ Poll summary marked as expired successfully for poll: #{event.poll_id}")
        :ok
        
      {:commit, {_old_value, %PollSummary{} = _updated_summary}} ->
        Logger.info("✅ Poll summary marked as expired successfully for poll: #{event.poll_id}")
        :ok
        
      {:ok, {nil, nil}} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:commit, {nil, nil}} ->
        Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
        {:error, :poll_summary_not_found}
        
      {:error, reason} ->
        Logger.error("❌ Failed to expire poll summary for poll: #{event.poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
end
