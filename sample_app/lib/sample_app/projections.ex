defmodule SampleApp.Projections do
  @moduledoc """
  Public API for querying read model projections.
  
  This module provides a clean interface for accessing cached projection data
  from the various read models maintained by the event handlers.
  """
  
  alias SampleApp.ReadModels.{PollSummary, PollResults, VoterHistory}
  
  @doc """
  Gets a poll summary by poll ID.
  """
  @spec get_poll_summary(String.t()) :: {:ok, PollSummary.t()} | {:error, :not_found}
  def get_poll_summary(poll_id) do
    case Cachex.get(:poll_summaries, poll_id) do
      {:ok, %PollSummary{} = summary} -> {:ok, summary}
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end
  
  @doc """
  Gets poll results by poll ID.
  """
  @spec get_poll_results(String.t()) :: {:ok, PollResults.t()} | {:error, :not_found}
  def get_poll_results(poll_id) do
    case Cachex.get(:poll_results, poll_id) do
      {:ok, %PollResults{} = results} -> {:ok, results}
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end
  
  @doc """
  Gets voter history by voter ID.
  """
  @spec get_voter_history(String.t()) :: {:ok, VoterHistory.t()} | {:error, :not_found}
  def get_voter_history(voter_id) do
    case Cachex.get(:voter_histories, voter_id) do
      {:ok, %VoterHistory{} = history} -> {:ok, history}
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end
  
  @doc """
  Lists all poll summaries (for admin/debugging purposes).
  """
  @spec list_all_poll_summaries() :: {:ok, [PollSummary.t()]} | {:error, term()}
  def list_all_poll_summaries() do
    case Cachex.keys(:poll_summaries) do
      {:ok, keys} ->
        summaries = 
          keys
          |> Enum.map(&get_poll_summary/1)
          |> Enum.filter(fn
            {:ok, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:ok, summary} -> summary end)
        
        {:ok, summaries}
      
      {:error, _reason} = error -> error
    end
  end
  
  @doc """
  Lists all active polls.
  """
  @spec list_active_polls() :: {:ok, [PollSummary.t()]} | {:error, term()}
  def list_active_polls() do
    case list_all_poll_summaries() do
      {:ok, summaries} ->
        active_polls = Enum.filter(summaries, fn summary -> summary.status == :active end)
        {:ok, active_polls}
        
      {:error, _reason} = error -> error
    end
  end
  
  @doc """
  Checks if a voter has already voted in a specific poll.
  """
  @spec has_voter_voted?(String.t(), String.t()) :: boolean()
  def has_voter_voted?(voter_id, poll_id) do
    case get_voter_history(voter_id) do
      {:ok, history} -> VoterHistory.has_voted?(history, poll_id)
      {:error, :not_found} -> false
    end
  end
  
  @doc """
  Gets cache statistics for monitoring.
  """
  @spec cache_stats() :: %{atom() => map()}
  def cache_stats() do
    %{
      poll_summaries: get_cache_stats(:poll_summaries),
      poll_results: get_cache_stats(:poll_results),
      voter_histories: get_cache_stats(:voter_histories)
    }
  end
  
  defp get_cache_stats(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} -> stats
      {:error, _reason} -> %{}
    end
  end
end
