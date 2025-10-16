defmodule SampleApp.QueryComparison do
  @moduledoc """
  Functions for comparing data between cache and database storage.
  Helps identify any inconsistencies between the two storage methods.
  """

  alias SampleApp.{
    QueryPollSummary,
    QueryPollResults,
    QueryVoterHistory
  }

  @doc """
  Compares poll summary data between cache and database for a specific poll.
  Returns any differences found.
  """
  def compare_poll_summary(poll_id) do
    with {:ok, cache_data} <- QueryPollSummary.FromCache.get_poll_summary(poll_id),
         {:ok, db_data} <- QueryPollSummary.FromDB.get_poll_summary(poll_id) do
      compare_data(cache_data, db_data)
    else
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Compares poll results data between cache and database for a specific poll.
  Returns any differences found.
  """
  def compare_poll_results(poll_id) do
    with {:ok, cache_data} <- QueryPollResults.FromCache.get_poll_results(poll_id),
         {:ok, db_data} <- QueryPollResults.FromDB.get_poll_results(poll_id) do
      compare_data(cache_data, db_data)
    else
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Compares voter history data between cache and database for a specific voter.
  Returns any differences found.
  """
  def compare_voter_history(voter_id) do
    with {:ok, cache_data} <- QueryVoterHistory.FromCache.get_voter_history(voter_id),
         {:ok, db_data} <- QueryVoterHistory.FromDB.get_voter_history(voter_id) do
      compare_data(cache_data, db_data)
    else
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Compares all poll summaries between cache and database.
  Returns any differences found.
  """
  def compare_all_poll_summaries() do
    with {:ok, cache_data} <- QueryPollSummary.FromCache.list_all_poll_summaries(),
         db_data <- QueryPollSummary.FromDB.list_all_poll_summaries() do
      # Sort both lists by poll_id to ensure consistent comparison
      compare_lists(
        Enum.sort_by(cache_data, & &1.poll_id),
        Enum.sort_by(db_data, & &1.poll_id)
      )
    end
  end

  @doc """
  Compares active polls between cache and database.
  Returns any differences found.
  """
  def compare_active_polls() do
    with {:ok, cache_data} <- QueryPollSummary.FromCache.list_active_polls(),
         db_data <- QueryPollSummary.FromDB.list_active_polls() do
      # Sort both lists by poll_id to ensure consistent comparison
      compare_lists(
        Enum.sort_by(cache_data, & &1.poll_id),
        Enum.sort_by(db_data, & &1.poll_id)
      )
    end
  end

  # Private helper functions

  defp compare_data(cache_data, db_data) do
    if cache_data == db_data do
      {:ok, :match}
    else
      {:mismatch, %{cache: cache_data, db: db_data}}
    end
  end

  defp compare_lists(cache_list, db_list) do
    cond do
      cache_list == db_list ->
        {:ok, :match}

      length(cache_list) != length(db_list) ->
        {:mismatch, %{
          reason: :length_mismatch,
          cache_length: length(cache_list),
          db_length: length(db_list)
        }}

      true ->
        # Find specific mismatches
        mismatches =
          Enum.zip(cache_list, db_list)
          |> Enum.with_index()
          |> Enum.flat_map(fn {{cache_item, db_item}, index} ->
            case compare_data(cache_item, db_item) do
              {:ok, :match} -> []
              {:mismatch, diff} -> [{index, diff}]
            end
          end)

        {:mismatch, %{differences: mismatches}}
    end
  end
end
