defmodule SampleApp.ReadModels.PollResults do
  @moduledoc """
  Read model for detailed poll results.

  Provides detailed results view with vote counts, percentages,
  and ranking of options.
  """

  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :title,
    :total_votes,
    # List of option results with counts and percentages
    :results,
    :status,
    :closed_at,
    :created_at,
    # Option with highest votes (nil if tie)
    :winner
  ]

  @type option_result :: %{
          option_id: String.t(),
          option_text: String.t(),
          vote_count: non_neg_integer(),
          percentage: float(),
          rank: pos_integer()
        }

  @type t :: %__MODULE__{
          poll_id: String.t(),
          title: String.t(),
          total_votes: non_neg_integer(),
          results: [option_result()],
          status: :active | :closed | :expired,
          closed_at: DateTime.t() | nil,
          created_at: DateTime.t(),
          winner: option_result() | nil
        }

  ## DELETED from_summary because ReadModels should be self-contained!

  @doc """
  Adds a vote to the poll results for a specific option.

  This function increments the vote count for the given option and recalculates
  percentages, rankings, and winner determination.
  """
  def add_vote(%__MODULE__{} = poll_results, option_id) do
    updated_results =
      poll_results.results
      |> Enum.map(fn result ->
        if result.option_id == option_id do
          %{result | vote_count: result.vote_count + 1}
        else
          result
        end
      end)
      |> recalculate_percentages_and_rankings(poll_results.total_votes + 1)

    winner = determine_winner(updated_results)

    %{
      poll_results
      | total_votes: poll_results.total_votes + 1,
        results: updated_results,
        winner: winner
    }
  end

  defp recalculate_percentages_and_rankings(results, total_votes) do
    results
    |> Enum.map(fn result ->
      percentage = if total_votes > 0, do: result.vote_count / total_votes * 100, else: 0.0
      %{result | percentage: Float.round(percentage, 2)}
    end)
    |> Enum.sort_by(& &1.vote_count, :desc)
    |> Enum.with_index(1)
    |> Enum.map(fn {result, rank} -> %{result | rank: rank} end)
  end

  defp determine_winner([]), do: nil

  defp determine_winner([first | rest]) do
    case Enum.find(rest, fn result -> result.vote_count == first.vote_count end) do
      # Clear winner
      nil -> first
      # It's a tie
      _tie -> nil
    end
  end
end
