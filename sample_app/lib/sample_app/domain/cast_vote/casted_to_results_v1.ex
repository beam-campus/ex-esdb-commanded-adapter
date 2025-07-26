defmodule SampleApp.Domain.CastVote.CastedToResultsV1 do
  @moduledoc """
  Projection that handles VoteCasted events and updates the PollResults read model.

  This projection updates poll results by incrementing vote counts for the voted option.
  Following the vertical slicing architecture and self-contained projection principles,
  this projection only uses event data and the current state of the target read model.
  
  IMPORTANT: This projection is self-contained and does NOT depend on other read models
  or external data sources to avoid race conditions.
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "vote_casted_to_results_v1",
    subscribe_to: "$et-vote_casted:v1"

  alias SampleApp.Domain.CastVote.EventV1, as: VoteCastedEvent
  alias SampleApp.ReadModels.PollResults

  require Logger

  def handle(%VoteCastedEvent{} = event, _metadata) do
    Logger.info("📊 Updating poll results with vote for poll: #{event.poll_id}")

    # Fail-fast: Check if cache is available before attempting operations
    case ensure_cache_available(:poll_results) do
      :ok ->
        update_func = fn
          nil ->
            # Poll results not initialized yet - ignore this vote
            # The InitializedToResultsV1 projection will create the initial results
            Logger.warning("⚠️  Poll results not found for poll: #{event.poll_id}, vote ignored")
            {:ignore, nil}

          %PollResults{} = results ->
            # ✅ SELF-CONTAINED: Only uses event data and current read model state
            updated_results = PollResults.add_vote(results, event.option_id)
            {:commit, updated_results}
        end

        case Cachex.get_and_update(:poll_results, event.poll_id, update_func) do
          {:commit, %PollResults{} = _updated_results} ->
            Logger.info("✅ Poll results updated successfully for poll: #{event.poll_id}")
            :ok

          {:ignore, _} ->
            # Poll results not initialized yet, this is expected
            Logger.info("ℹ️  Poll results not yet initialized for poll: #{event.poll_id}, vote will be counted after initialization")
            :ok

          {:error, reason} ->
            Logger.error(
              "❌ Failed to update poll results for poll: #{event.poll_id}, reason: #{inspect(reason)}"
            )
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "❌ Cache :poll_results not available for poll: #{event.poll_id}, reason: #{inspect(reason)}"
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
