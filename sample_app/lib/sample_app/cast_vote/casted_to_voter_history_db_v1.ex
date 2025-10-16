defmodule SampleApp.CastVote.CastedToVoterHistoryDBV1 do
  @moduledoc """
  Handles updating voter history in database when votes are cast.
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
    query = from h in Schemas.VoterHistory,
            where: h.voter_id == ^event.voter_id,
            select: h

    voter_history = case Repo.one(query) do
      nil -> %Schemas.VoterHistory{
        voter_id: event.voter_id,
        poll_votes: [],
        total_votes_cast: 0
      }
      existing -> existing
    end

    new_vote = %{
      poll_id: event.poll_id,
      option_id: event.option_id,
      voted_at: event.casted_at
    }

    changeset = Ecto.Changeset.change(voter_history, %{
      poll_votes: [new_vote | voter_history.poll_votes],
      last_vote_at: event.casted_at,
      total_votes_cast: voter_history.total_votes_cast + 1
    })

    case upsert_voter_history(voter_history, changeset) do
      {:ok, _history} ->
        {:noreply, state}

      {:error, changeset} ->
        Logger.error("⚠️ Failed to update voter history in DB: #{inspect(changeset.errors)}")
        {:noreply, state}
    end
  end

  defp upsert_voter_history(%{voter_id: nil}, changeset) do
    Repo.insert(changeset)
  end

  defp upsert_voter_history(_existing, changeset) do
    Repo.update(changeset)
  end
end
