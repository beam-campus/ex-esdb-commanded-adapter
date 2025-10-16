defmodule SampleApp.CastVote.CastedToPollResultsDBV1 do
  @moduledoc """
  Handles updating poll results in database when votes are cast.
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
    query = from r in Schemas.PollResults,
            where: r.poll_id == ^event.poll_id,
            select: r

    case Repo.one(query) do
      nil ->
        Logger.error("⚠️ No poll results found in DB for: #{event.poll_id}")
        {:noreply, state}

      results ->
        # Update vote counts and recalculate percentages
        updated_options = 
          results.results.options
          |> Enum.map(fn result ->
            if result.option_id == event.option_id do
              Map.update!(result, :vote_count, &(&1 + 1))
            else
              result
            end
          end)
          |> recalculate_percentages_and_rankings(results.total_votes + 1)
          
        updated_results = %{
          options: updated_options,
          updated_at: DateTime.utc_now()
        }

        winner = determine_winner(updated_options)
        
        changeset = Ecto.Changeset.change(results, %{
          total_votes: results.total_votes + 1,
          results: updated_results,
          winner: winner
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

  defp recalculate_percentages_and_rankings(options, total_votes) do
    options
    |> Enum.map(fn result ->
      percentage = if total_votes > 0, do: result.vote_count / total_votes * 100, else: 0.0
      Map.put(result, :percentage, Float.round(percentage, 2))
    end)
    |> Enum.sort_by(&Map.get(&1, :vote_count), :desc)
    |> Enum.with_index(1)
    |> Enum.map(fn {result, rank} -> Map.put(result, :rank, rank) end)
  end

  defp determine_winner([]), do: nil
  defp determine_winner([first | rest]) do
    case Enum.find(rest, fn result -> result.vote_count == first.vote_count end) do
      nil -> first  # Clear winner
      _tie -> nil   # It's a tie
    end
  end
end
