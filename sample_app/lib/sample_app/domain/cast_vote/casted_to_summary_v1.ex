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
    Logger.info(
      "🗳️  Updating poll summary with vote for poll: #{event.poll_id}, option: #{event.option_id}"
    )

    # Fail-fast: Check if cache is available before attempting operations
    case ensure_cache_available(:poll_summaries) do
      :ok ->
        update_func = fn
          nil ->
            {:ignore, nil}

          %PollSummary{} = summary ->
            updated_summary = PollSummary.add_vote(summary, event.option_id)
            {:commit, updated_summary}
        end

        case Cachex.get_and_update(:poll_summaries, event.poll_id, update_func) do
          {:commit, %PollSummary{} = _updated_summary} ->
            Logger.info("✅ Poll summary updated successfully for poll: #{event.poll_id}")
            :ok

          {:ignore, _} ->
            Logger.warning("⚠️  Poll summary not found for poll: #{event.poll_id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "❌ Failed to update poll summary for poll: #{event.poll_id}, reason: #{inspect(reason)}"
            )
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
