defmodule SampleApp.VotingREPL.Reader do
  @moduledoc """
  Read-side operations for the VotingREPL interface.
  Handles all query operations like getting results, listing polls, etc.
  """

  # DB Query modules
  alias SampleApp.QueryPollSummary.FromDB, as: PollSummaryDB
  alias SampleApp.QueryPollResults.FromDB, as: PollResultsDB
  alias SampleApp.QueryPollSummary.{FromCache, FromDB}
  alias SampleApp.QueryPollResults.{FromCache, FromDB}
  alias SampleApp.QueryVoterHistory.{FromCache, FromDB}

  @doc """
  Get poll results.

  ## Examples

      iex> results("poll-123")
      "📊 Results for poll-123"
  """
  def results(poll_id) do
    IO.puts("📊 Results for #{poll_id}")
    
    case PollResultsDB.get_poll_results(poll_id) do
      {:ok, results} ->
        display_poll_results(results)
        "📊 Results for #{poll_id}"
        
      {:error, :not_found} ->
        IO.puts("❌ Poll not found: #{poll_id}")
        "❌ Poll not found: #{poll_id}"
        
      {:error, reason} ->
        IO.puts("❌ Error retrieving results: #{inspect(reason)}")
        "❌ Error retrieving results"
    end
  end

  @doc """
  Lists all active polls from the database.

  ## Examples

      iex> list_active_polls()
      :ok
  """
  def list_active_polls do
    polls = PollSummaryDB.list_active_polls()
    
    if polls == [] do
      IO.puts("📭 No active polls found.")
    else
      IO.puts("📋 Active Polls:")
      IO.puts("")
      
      Enum.each(polls, fn poll ->
        IO.puts("  🗳️  #{poll.poll_id}")
        IO.puts("     📝 #{poll.title}")
        IO.puts("     👤 Created by: #{poll.created_by}")
        IO.puts("     📅 Created: #{Calendar.strftime(poll.created_at, "%Y-%m-%d %H:%M:%S")}")
        if poll.expires_at do
          IO.puts("     ⏰ Expires: #{Calendar.strftime(poll.expires_at, "%Y-%m-%d %H:%M:%S")}")
        end
        IO.puts("     📊 Total votes: #{poll.total_votes}")
        IO.puts("")
      end)
    end
    :ok
  end

  @doc """
  Gets poll results for all polls a voter has participated in.

  ## Examples

      iex> voter_results("alice")
      :ok
  """
  def voter_results(voter_id) do
    results = PollResultsDB.get_results_by_voter(voter_id)
    
    if results == [] do
      IO.puts("📭 No voting history found for #{voter_id}")
    else
      IO.puts("📋 Voting History for #{voter_id}:")
      IO.puts("")
      
      Enum.each(results, fn result ->
        display_poll_results(result)
      end)
    end
    :ok
  end

  @doc """
  Lists results for all closed polls.

  ## Examples

      iex> list_closed_polls()
      :ok
  """
  def list_closed_polls do
    results = PollResultsDB.list_closed_poll_results()
    
    if results == [] do
      IO.puts("📭 No closed polls found.")
    else
      IO.puts("📋 Closed Polls:")
      IO.puts("")
      
      Enum.each(results, fn result ->
        display_poll_results(result)
      end)
    end
    :ok
  end

  @doc """
  Lists all polls from the database.

  ## Examples

      iex> list_all_polls()
      :ok
  """
  def list_all_polls do
    polls = PollSummaryDB.list_all_poll_summaries()
    
    if polls == [] do
      IO.puts("📭 No polls found in database.")
    else
      IO.puts("📋 All Polls:")
      IO.puts("")
      
      Enum.each(polls, fn poll ->
        status = case poll.status do
          :active -> "✅ ACTIVE"
          :closed -> "🔒 CLOSED"
          :expired -> "⏰ EXPIRED"
        end

        IO.puts("  🗳️  #{poll.poll_id}")
        IO.puts("     📝 #{poll.title}")
        IO.puts("     👤 Created by: #{poll.created_by}")
        IO.puts("     📅 Created: #{Calendar.strftime(poll.created_at, "%Y-%m-%d %H:%M:%S")}")
        IO.puts("     📊 Status: #{status}")
        IO.puts("     📈 Total votes: #{poll.total_votes}")
        IO.puts("")
      end)
    end
    :ok
  end

  @doc """
  Compare poll summary between cache and database.

  ## Examples

      iex> compare_poll_summary("poll-123")
      :ok
  """
  def compare_poll_summary(poll_id) do
    cache_result = FromCache.get_poll_summary(poll_id)
    db_result = FromDB.get_poll_summary(poll_id)

    IO.puts("📋 Poll Summary Comparison for #{poll_id}:")
    IO.puts("")
    IO.puts("Cache:")
    display_poll_summary(cache_result)
    IO.puts("")
    IO.puts("Database:")
    display_poll_summary(db_result)
    :ok
  end

  @doc """
  Compare poll results between cache and database.

  ## Examples

      iex> compare_poll_results("poll-123")
      :ok
  """
  def compare_poll_results(poll_id) do
    cache_result = FromCache.get_poll_results(poll_id)
    db_result = FromDB.get_poll_results(poll_id)

    IO.puts("📊 Poll Results Comparison for #{poll_id}:")
    IO.puts("")
    IO.puts("Cache:")
    display_poll_results(cache_result)
    IO.puts("")
    IO.puts("Database:")
    display_poll_results(db_result)
    :ok
  end

  @doc """
  Compare voter history between cache and database.

  ## Examples

      iex> compare_voter_history("alice")
      :ok
  """
  def compare_voter_history(voter_id) do
    cache_result = FromCache.get_voter_history(voter_id)
    db_result = FromDB.get_voter_history(voter_id)

    IO.puts("👤 Voter History Comparison for #{voter_id}:")
    IO.puts("")
    IO.puts("Cache:")
    display_voter_history(cache_result)
    IO.puts("")
    IO.puts("Database:")
    display_voter_history(db_result)
    :ok
  end

  @doc """
  Compare all poll summaries between cache and database.

  ## Examples

      iex> compare_all_poll_summaries()
      :ok
  """
  def compare_all_poll_summaries do
    cache_polls = FromCache.list_all_poll_summaries()
    db_polls = FromDB.list_all_poll_summaries()

    IO.puts("📋 All Poll Summaries Comparison:")
    IO.puts("")
    IO.puts("Cache (#{length(cache_polls)} polls):")
    display_poll_summaries(cache_polls)
    IO.puts("")
    IO.puts("Database (#{length(db_polls)} polls):")
    display_poll_summaries(db_polls)
    :ok
  end

  @doc """
  Compare active polls between cache and database.

  ## Examples

      iex> compare_active_polls()
      :ok
  """
  def compare_active_polls do
    cache_polls = FromCache.list_active_polls()
    db_polls = FromDB.list_active_polls()

    IO.puts("📋 Active Polls Comparison:")
    IO.puts("")
    IO.puts("Cache (#{length(cache_polls)} active polls):")
    display_poll_summaries(cache_polls)
    IO.puts("")
    IO.puts("Database (#{length(db_polls)} active polls):")
    display_poll_summaries(db_polls)
    :ok
  end

  @doc """
  Get cache statistics including total polls, active polls, etc.

  ## Examples

      iex> cache_stats()
      :ok
  """
  def cache_stats do
    all_polls = FromCache.list_all_poll_summaries()
    active_polls = FromCache.list_active_polls()
    closed_polls = Enum.filter(all_polls, & &1.status == :closed)
    expired_polls = Enum.filter(all_polls, & &1.status == :expired)

    IO.puts("📊 Cache Statistics:")
    IO.puts("")
    IO.puts("Total Polls: #{length(all_polls)}")
    IO.puts("Active Polls: #{length(active_polls)}")
    IO.puts("Closed Polls: #{length(closed_polls)}")
    IO.puts("Expired Polls: #{length(expired_polls)}")
    :ok
  end

  @doc """
  Get detailed poll information from the database.

  ## Examples

      iex> poll_details("poll-123")
      :ok
  """
  def poll_details(poll_id) do
    case PollSummaryDB.get_poll_summary(poll_id) do
      {:ok, poll} ->
        IO.puts("🗳️  Poll Information")
        IO.puts("=" |> String.duplicate(50))
        IO.puts("📋 ID: #{poll_id}")
        IO.puts("📝 Title: #{poll.title}")
        IO.puts("👤 Creator: #{poll.creator}")
        IO.puts("📅 Created: #{Calendar.strftime(poll.created_at, "%Y-%m-%d %H:%M:%S UTC")}")
        
        if poll.expires_at do
          IO.puts("⏰ Expires: #{Calendar.strftime(poll.expires_at, "%Y-%m-%d %H:%M:%S UTC")}")
        end
        if poll.closed_at do
          IO.puts("🔒 Closed: #{Calendar.strftime(poll.closed_at, "%Y-%m-%d %H:%M:%S UTC")}")
        end
        
        IO.puts("📊 Status: #{format_status(poll.status)}")
        IO.puts("📊 Total Votes: #{poll.total_votes}")
        
        IO.puts("\n🎯 Vote Distribution:")
        Enum.each(poll.vote_counts, fn {option_id, count} ->
          percentage = if poll.total_votes > 0, do: count / poll.total_votes * 100, else: 0.0
          bar = create_progress_bar(percentage)
          IO.puts("   #{option_id}: #{count} votes (#{Float.round(percentage, 1)}%) #{bar}")
        end)
        
        IO.puts("")
        IO.puts("💡 Use these commands to interact:")
        IO.puts("   vote(\"#{poll_id}\", \"option_1\", \"your_name\")")
        if poll.status == :active do
          IO.puts("   close_poll(\"#{poll_id}\")")
        end
        :ok
        
      {:error, :not_found} ->
        IO.puts("❌ Poll not found in database: #{poll_id}")
        {:error, :not_found}
    end
  end

  # Private helper functions for displaying poll information

  defp display_poll_summary({:ok, poll}) do
    status = case poll.status do
      :active -> "✅ ACTIVE"
      :closed -> "🔒 CLOSED"
      :expired -> "⏰ EXPIRED"
    end

    IO.puts("  🗳️  #{poll.poll_id}")
    IO.puts("     📝 #{poll.title}")
    IO.puts("     👤 Created by: #{poll.created_by}")
    IO.puts("     📅 Created: #{Calendar.strftime(poll.created_at, "%Y-%m-%d %H:%M:%S")}")
    IO.puts("     📊 Status: #{status}")
    IO.puts("     📈 Total votes: #{poll.total_votes}")
  end

  defp display_poll_summary({:error, :not_found}) do
    IO.puts("  ❌ Poll not found")
  end

  defp display_poll_summary({:error, reason}) do
    IO.puts("  ❌ Error: #{inspect(reason)}")
  end

  defp display_poll_summaries(polls) do
    if polls == [] do
      IO.puts("  📭 No polls found")
    else
      Enum.each(polls, fn poll ->
        display_poll_summary({:ok, poll})
        IO.puts("")
      end)
    end
  end

  defp display_voter_history({:ok, history}) do
    if history == [] do
      IO.puts("  📭 No voting history found")
    else
      Enum.each(history, fn vote ->
        IO.puts("  🗳️  Poll: #{vote.poll_id}")
        IO.puts("     📝 Title: #{vote.poll_title}")
        IO.puts("     🎯 Voted for: #{vote.option_text}")
        IO.puts("     📅 Voted at: #{Calendar.strftime(vote.voted_at, "%Y-%m-%d %H:%M:%S")}")
        IO.puts("")
      end)
    end
  end

  defp display_voter_history({:error, :not_found}) do
    IO.puts("  ❌ Voter not found")
  end

  defp display_voter_history({:error, reason}) do
    IO.puts("  ❌ Error: #{inspect(reason)}")
  end

  defp display_poll_results({:ok, results}) do
    IO.puts("  📋 #{results.title}")
    IO.puts("  📊 Total votes: #{results.total_votes}")
    IO.puts("")

    if results.status == :closed || results.status == :expired do
      if results.winner do
        IO.puts("  🏆 Winner: #{results.winner.option_text}")
        IO.puts("     📈 Votes: #{results.winner.vote_count}")
        IO.puts("     📊 Percentage: #{Float.round(results.winner.percentage, 1)}%")
        IO.puts("")
      else
        IO.puts("  🤝 No winner (tie)")
        IO.puts("")
      end
    end

    IO.puts("  📊 Results:")
    results.results
    |> Enum.sort_by(& &1.rank)
    |> Enum.each(fn result ->
      percentage = Float.round(result.percentage, 1)
      bar_length = trunc(percentage / 2)
      bar = String.duplicate("█", bar_length)

      IO.puts("     #{result.rank}. #{result.option_text}")
      IO.puts("        #{bar} #{percentage}% (#{result.vote_count} votes)")
    end)
  end

  defp display_poll_results({:error, :not_found}) do
    IO.puts("  ❌ Poll results not found")
  end

  defp display_poll_results({:error, reason}) do
    IO.puts("  ❌ Error: #{inspect(reason)}")
  end

  defp format_status(:active), do: "✅ ACTIVE"
  defp format_status(:closed), do: "🔒 CLOSED"
  defp format_status(:expired), do: "⏰ EXPIRED"

  defp create_progress_bar(percentage) when percentage == 0, do: "⬜⬜⬜⬜⬜"
  defp create_progress_bar(percentage) do
    filled = round(percentage / 20)
    empty = 5 - filled
    String.duplicate("🟩", filled) <> String.duplicate("⬜", empty)
  end
end
