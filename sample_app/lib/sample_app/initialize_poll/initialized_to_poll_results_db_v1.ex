defmodule SampleApp.InitializePoll.InitializedToPollResultsDBV1 do
  @moduledoc """
  Handles storing poll results in database when a poll is initialized.
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
    poll_results = %Schemas.PollResults{
      poll_id: event.poll_id,
      title: event.title,
      total_votes: 0,
      results: initialize_results(event.options),
      status: :active,
      closed_at: nil,
      created_at: DateTime.truncate(event.initialized_at, :second),
      winner: nil
    }

    case Repo.insert(poll_results) do
      {:ok, _results} ->
        {:noreply, state}

      {:error, changeset} ->
        Logger.error("⚠️ Failed to save poll results to DB: #{inspect(changeset.errors)}")
        {:noreply, state}
    end
  end

  defp initialize_results(options) do
    results = options
    |> Enum.map(fn option ->
      %{
        option_id: option.id,
        option_text: option.text,
        vote_count: 0,
        percentage: 0.0,
        rank: 1
      }
    end)
    
    %{
      options: results,
      updated_at: DateTime.utc_now()
    }
  end
end
