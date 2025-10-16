defmodule SampleApp.ClosePoll.PollClosedToPollResultsDBV1 do
  @moduledoc """
  Handles updating poll results in database when a poll is closed.
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

  def handle_info({:poll_closed, event}, state) do
    query = from r in Schemas.PollResults,
            where: r.poll_id == ^event.poll_id,
            select: r

    case Repo.one(query) do
      nil ->
        Logger.error("⚠️ No poll results found in DB for: #{event.poll_id}")
        {:noreply, state}

      results ->
        changeset = Ecto.Changeset.change(results, %{
          status: :closed,
          closed_at: event.closed_at
        })

        case Repo.update(changeset) do
          {:ok, _updated} ->
            {:noreply, state}

          {:error, changeset} ->
            Logger.error("⚠️ Failed to update poll results in DB: #{inspect(changeset.errors)}")
            {:noreply, state}
        end
    end
  end
end
