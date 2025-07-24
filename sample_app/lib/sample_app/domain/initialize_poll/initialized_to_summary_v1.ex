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
    
    summary = PollSummary.from_initialization(event)
    
    case Cachex.put(:poll_summaries, event.poll_id, summary) do
      {:ok, true} ->
        Logger.info("✅ Poll summary created successfully for poll: #{event.poll_id}")
        :ok
        
      {:error, reason} ->
        Logger.error("❌ Failed to create poll summary for poll: #{event.poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
