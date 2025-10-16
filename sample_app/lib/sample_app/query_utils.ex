defmodule SampleApp.QueryUtils do
  @moduledoc """
  Shared utilities for query operations, primarily focused on cache management.
  """

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

  @doc """
  Gets statistics for a specific cache.
  """
  @spec get_cache_stats(atom()) :: map()
  def get_cache_stats(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} -> stats
      {:error, _reason} -> %{}
    end
  end
end
