defmodule SampleApp.Domain.InitializePoll.InitializedToResultsV1 do
  @moduledoc """
  Projection that handles PollInitialized events and updates the PollResults read model.
  
  This projection creates initial poll results entries in the poll_results cache when polls are initialized.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """
  
  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "poll_initialized_to_results_v1",
    subscribe_to: "$et-poll_initialized:v1"
  
  alias SampleApp.Domain.InitializePoll.EventV1, as: PollInitializedEvent
  alias SampleApp.ReadModels.{PollSummary, PollResults}
  
  require Logger
  
  def handle(%PollInitializedEvent{} = event, _metadata) do
    Logger.info("📊 Creating poll results for poll: #{event.poll_id}")
    
    # Create an initial summary to generate results from
    summary = PollSummary.from_initialization(event)
    results = PollResults.from_summary(summary, event.options)
    
    case Cachex.put(:poll_results, event.poll_id, results) do
      {:ok, true} ->
        Logger.info("✅ Poll results created successfully for poll: #{event.poll_id}")
        :ok
        
      {:error, reason} ->
        Logger.error("❌ Failed to create poll results for poll: #{event.poll_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
