defmodule SampleApp.CastVote.CastedToPollSummaryDBV1 do
  @moduledoc """
  Handles updating poll summary in database when votes are cast.
  """
  use GenServer
  alias SampleApp.{Repo, Schemas}
  require Logger
  import Ecto.Query

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ok = Phoenix.PubSub.subscribe(SampleApp.PubSub, "poll_events")
    {:ok, %{}}
  end

  def handle_info({:vote_casted, event}, state) do
    query = from s in Schemas.PollSummary,
            where: s.poll_id == ^event.poll_id,
            select: s

    case Repo.one(query) do
      nil ->
        Logger.error("⚠️ No poll summary found in DB for: #{event.poll_id}")
        {:noreply, state}

      summary ->
        updated_vote_counts = Map.update(summary.vote_counts, event.option_id, 1, &(&1 + 1))
        
        changeset = Ecto.Changeset.change(summary, %{
          total_votes: summary.total_votes + 1,
          vote_counts: updated_vote_counts
        })

        case Repo.update(changeset) do
          {:ok, _updated} ->
            {:noreply, state}

          {:error, changeset} ->
            Logger.error("⚠️ Failed to update poll summary in DB: #{inspect(changeset.errors)}")
            {:noreply, state}
        end
    end
  end
end
