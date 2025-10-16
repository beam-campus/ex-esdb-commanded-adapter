defmodule SampleApp.QueryAPI do
  @moduledoc """
  Public API for all query operations.
  
  This module provides a unified interface to all query operations,
  delegating to specific query slices for implementation.
  """

  alias SampleApp.QueryPollSummary
  alias SampleApp.QueryPollResults
  alias SampleApp.QueryVoterHistory
  alias SampleApp.QueryUtils

  # Poll Summary operations
  # Poll Summary operations
  defdelegate get_poll_summary_from_cache(poll_id), to: QueryPollSummary.FromCache, as: :get_poll_summary
  defdelegate list_all_poll_summaries_from_cache(), to: QueryPollSummary.FromCache, as: :list_all_poll_summaries
  defdelegate list_active_polls_from_cache(), to: QueryPollSummary.FromCache, as: :list_active_polls

  defdelegate get_poll_summary_from_db(poll_id), to: QueryPollSummary.FromDB, as: :get_poll_summary
  defdelegate list_all_poll_summaries_from_db(), to: QueryPollSummary.FromDB, as: :list_all_poll_summaries
  defdelegate list_active_polls_from_db(), to: QueryPollSummary.FromDB, as: :list_active_polls
  
  # Poll Results operations
  defdelegate get_poll_results_from_cache(poll_id), to: QueryPollResults.FromCache, as: :get_poll_results
  defdelegate get_poll_results_from_db(poll_id), to: QueryPollResults.FromDB, as: :get_poll_results

  # Voter History operations
  defdelegate get_voter_history_from_cache(voter_id), to: QueryVoterHistory.FromCache, as: :get_voter_history
  defdelegate get_voter_history_from_db(voter_id), to: QueryVoterHistory.FromDB, as: :get_voter_history
  defdelegate has_voter_voted_from_cache?(voter_id, poll_id), to: QueryVoterHistory.FromCache, as: :has_voter_voted?
  defdelegate has_voter_voted_from_db?(voter_id, poll_id), to: QueryVoterHistory.FromDB, as: :has_voter_voted?

  # Comparison operations
  defdelegate compare_poll_summary(poll_id), to: SampleApp.QueryComparison
  defdelegate compare_poll_results(poll_id), to: SampleApp.QueryComparison
  defdelegate compare_voter_history(voter_id), to: SampleApp.QueryComparison
  defdelegate compare_all_poll_summaries(), to: SampleApp.QueryComparison
  defdelegate compare_active_polls(), to: SampleApp.QueryComparison

  # Cache statistics
  defdelegate cache_stats(), to: QueryUtils
end
