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
    :results,     # List of option results with counts and percentages
    :status,
    :closed_at,
    :winner      # Option with highest votes (nil if tie)
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
    winner: option_result() | nil
  }
  
  @doc """
  Creates poll results from a poll summary.
  """
  def from_summary(%SampleApp.ReadModels.PollSummary{} = summary, options) do
    results = calculate_results(summary.vote_counts, options, summary.total_votes)
    winner = determine_winner(results)
    
    %__MODULE__{
      poll_id: summary.poll_id,
      title: summary.title,
      total_votes: summary.total_votes,
      results: results,
      status: summary.status,
      closed_at: summary.closed_at,
      winner: winner
    }
  end
  
  defp calculate_results(vote_counts, options, total_votes) do
    option_map = Enum.into(options, %{}, fn option -> {option.id, option.text} end)
    
    vote_counts
    |> Enum.map(fn {option_id, count} ->
      percentage = if total_votes > 0, do: count / total_votes * 100, else: 0.0
      
      %{
        option_id: option_id,
        option_text: Map.get(option_map, option_id, "Unknown Option"),
        vote_count: count,
        percentage: Float.round(percentage, 2)
      }
    end)
    |> Enum.sort_by(& &1.vote_count, :desc)
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
