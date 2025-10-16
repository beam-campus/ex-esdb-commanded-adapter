defmodule SampleApp.InitializePoll.InitializedToPollSummaryDBV1 do
  @moduledoc """
  Handles storing poll initialization events in the database.
  """
  use GenServer
  alias SampleApp.{Repo, Schemas}
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ok = Phoenix.PubSub.subscribe(SampleApp.PubSub, "poll_projections")
    {:ok, %{}}
  end

  def handle_info({:poll_initialized, event}, state) do
    poll_summary = %Schemas.PollSummary{
      poll_id: event.poll_id,
      title: event.title,
      description: event.description,
      created_by: event.created_by,
      status: :active,
      total_votes: 0,
      vote_counts: initialize_vote_counts(event.options),
      expires_at: if(event.expires_at, do: DateTime.truncate(event.expires_at, :second)),
      created_at: DateTime.truncate(event.initialized_at, :second),
      closed_at: nil
    }

    case Repo.insert(poll_summary) do
      {:ok, _summary} ->
        {:noreply, state}

      {:error, changeset} ->
        Logger.error("⚠️ Failed to save poll summary to DB: #{inspect(changeset.errors)}")
        {:noreply, state}
    end
  end

  defp initialize_vote_counts(options) do
    options
    |> Enum.into(%{}, fn option -> {option.id, 0} end)
  end
end
