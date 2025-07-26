defmodule SampleApp.Domain.CastVote.CastedToVoterHistoryV1 do
  @moduledoc """
  Projection that handles VoteCasted events and updates the VoterHistory read model.

  This projection tracks voter history by updating voter records in the voter_histories
  cache when votes are cast.
  Following the vertical slicing architecture, this projection lives in the same slice
  as the event it processes.
  """

  use Commanded.Event.Handler,
    application: SampleApp.CommandedApp,
    name: "vote_casted_to_voter_history_v1",
    subscribe_to: "$et-vote_casted:v1"

  alias SampleApp.Domain.CastVote.EventV1, as: VoteCastedEvent
  alias SampleApp.ReadModels.VoterHistory

  require Logger

  def handle(%VoteCastedEvent{} = event, _metadata) do
    Logger.info("📋 Updating voter history for voter: #{event.voter_id}, poll: #{event.poll_id}")

    update_func = fn
      nil ->
        # Create new voter history record
        new_history = VoterHistory.new(event.voter_id)

        updated_history =
          VoterHistory.add_vote(new_history, event.poll_id, event.option_id, event.voted_at)

        {nil, updated_history}

      %VoterHistory{} = history ->
        # Update existing voter history
        updated_history =
          VoterHistory.add_vote(history, event.poll_id, event.option_id, event.voted_at)

        {history, updated_history}
    end

    case Cachex.get_and_update(:voter_histories, event.voter_id, update_func) do
      {:ok, {_old_value, %VoterHistory{} = _updated_history}} ->
        Logger.info("✅ Voter history updated successfully for voter: #{event.voter_id}")
        :ok

      {:commit, {_old_value, %VoterHistory{} = _updated_history}} ->
        Logger.info("✅ Voter history updated successfully for voter: #{event.voter_id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ Failed to update voter history for voter: #{event.voter_id}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
