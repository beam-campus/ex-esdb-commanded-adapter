defmodule SampleApp.ClosePoll.PollClosedToPollSummaryDBV1 do
  @moduledoc """
  Handles updating poll summary in database when a poll is closed.
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
    query = from s in Schemas.PollSummary,
            where: s.poll_id == ^event.poll_id,
            select: s

    case Repo.one(query) do
      nil ->
        Logger.error("⚠️ No poll summary found in DB for: #{event.poll_id}")
        {:noreply, state}

      summary ->
        changeset = Ecto.Changeset.change(summary, %{
          status: :closed,
          closed_at: event.closed_at
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
