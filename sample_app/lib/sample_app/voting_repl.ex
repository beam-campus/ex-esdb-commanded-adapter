defmodule SampleApp.VotingREPL do
  @moduledoc """
  User-friendly REPL interface for interacting with the voting system domain.
  
  This module provides simple functions to demonstrate and test the complete
  poll lifecycle using natural language function names.
  
  ## Usage
  
      iex> alias SampleApp.VotingREPL, as: Voting
      iex> Voting.create_poll("Favorite Color?", ["Red", "Blue", "Green"])
      iex> Voting.vote("poll-123", "option_1", "alice")
      iex> Voting.results("poll-123")
      iex> Voting.close_poll("poll-123", "admin")
  
  ## Available Functions
  
  - `create_poll/3` - Create a new poll
  - `create_poll_with_expiration/4` - Create a poll that expires
  - `vote/3` - Cast a vote on a poll
  - `close_poll/2` - Manually close a poll
  - `results/1` - Get current poll results (placeholder)
  - `list_polls/0` - List recent polls created in this session
  - `help/0` - Show available commands
  
  """
  
  alias SampleApp.CommandedApp
  alias SampleApp.Domain.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.Domain.CastVote.CommandV1, as: CastVoteCommand
  alias SampleApp.Domain.ClosePoll.CommandV1, as: ClosePollCommand
  alias SampleApp.Domain.ExpireCountdown.CommandV1, as: ExpireCountdownCommand
  alias SampleApp.Domain.StartExpirationCountdown.CommandV1, as: StartExpirationCountdownCommand
  
  require Logger
  
  # Track polls created in this session
  @polls_table :voting_repl_polls
  
  def __init__ do
    # Initialize ETS table for tracking polls if it doesn't exist
    unless :ets.whereis(@polls_table) != :undefined do
      :ets.new(@polls_table, [:set, :public, :named_table])
    end
  end
  
  @doc """
  Shows available commands and usage examples.
  """
  def help do
    IO.puts("""
    
    🗳️  SampleApp Voting System REPL Interface
    ==========================================
    
    Available Commands:
    
    📋 Poll Management:
      create_poll(title, options, creator \\ "system")
      create_poll_with_expiration(title, options, expires_in_seconds, creator \\ "system")
      close_poll(poll_id, closer \\ "system")
      
    🗳️  Voting:
      vote(poll_id, option_id, voter_id)
      
    📊 Information:
      results(poll_id)              # Get poll results (placeholder)
      list_polls()                  # List polls from this session
      poll_info(poll_id)            # Get detailed poll information
      
    ⏰ Advanced:
      start_countdown(poll_id, expires_at)    # Manually start expiration countdown
      expire_poll(poll_id)                    # Manually expire a poll
      
    📚 Examples:
    
      # Create a simple poll
      create_poll("Favorite Language?", ["Elixir", "Rust", "Go"])
      
      # Create a poll with 1 hour expiration
      create_poll_with_expiration("Quick Poll", ["Yes", "No"], 3600)
      
      # Vote on a poll (use option_1, option_2, etc.)
      vote("poll-123", "option_1", "alice")
      vote("poll-123", "option_2", "bob")
      
      # Close a poll manually
      close_poll("poll-123")
      
      # Check results
      results("poll-123")
    
    """)
    :ok
  end
  
  @doc """
  Creates a new poll with the given title and options.
  
  Returns the poll ID for use with other functions.
  
  ## Examples
  
      iex> create_poll("Favorite Color?", ["Red", "Blue", "Green"])
      {:ok, "poll-1234567890"}
      
      iex> create_poll("Best Framework?", ["Phoenix", "Rails", "Django"], "alice")
      {:ok, "poll-1234567891"}
  """
  def create_poll(title, options, creator \\ "system") when is_list(options) and length(options) >= 2 do
    poll_id = generate_poll_id()
    
    command = %InitializePollCommand{
      poll_id: poll_id,
      title: title,
      description: "Created via REPL",
      options: options,
      created_by: creator,
      requested_at: DateTime.utc_now(),
      expires_at: nil
    }
    
    case CommandedApp.dispatch(command) do
      :ok ->
        store_poll_info(poll_id, title, options, creator, nil)
        IO.puts("✅ Poll created successfully!")
        IO.puts("📋 Poll ID: #{poll_id}")
        IO.puts("🎯 Title: #{title}")
        IO.puts("📝 Options: #{format_options_with_ids(options)}")
        {:ok, poll_id}
        
      {:error, reason} ->
        IO.puts("❌ Failed to create poll: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Creates a new poll with an expiration time.
  
  ## Examples
  
      iex> create_poll_with_expiration("Quick Vote", ["Yes", "No"], 3600)
      {:ok, "poll-1234567892"}
  """
  def create_poll_with_expiration(title, options, expires_in_seconds, creator \\ "system") do
    poll_id = generate_poll_id()
    expires_at = DateTime.add(DateTime.utc_now(), expires_in_seconds)
    
    command = %InitializePollCommand{
      poll_id: poll_id,
      title: title,
      description: "Created via REPL with expiration",
      options: options,
      created_by: creator,
      requested_at: DateTime.utc_now(),
      expires_at: expires_at
    }
    
    case CommandedApp.dispatch(command) do
      :ok ->
        store_poll_info(poll_id, title, options, creator, expires_at)
        IO.puts("✅ Poll with expiration created successfully!")
        IO.puts("📋 Poll ID: #{poll_id}")
        IO.puts("🎯 Title: #{title}")
        IO.puts("📝 Options: #{format_options_with_ids(options)}")
        IO.puts("⏰ Expires at: #{Calendar.strftime(expires_at, "%Y-%m-%d %H:%M:%S UTC")}")
        {:ok, poll_id}
        
      {:error, reason} ->
        IO.puts("❌ Failed to create poll: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Cast a vote on the specified poll.
  
  Use option IDs like "option_1", "option_2", etc.
  
  ## Examples
  
      iex> vote("poll-123", "option_1", "alice")
      :ok
      
      iex> vote("poll-123", "option_2", "bob")
      :ok
  """
  def vote(poll_id, option_id, voter_id) do
    command = %CastVoteCommand{
      poll_id: poll_id,
      option_id: option_id,
      voter_id: voter_id,
      requested_at: DateTime.utc_now()
    }
    
    case CommandedApp.dispatch(command) do
      :ok ->
        IO.puts("✅ Vote cast successfully!")
        IO.puts("🗳️  Voter: #{voter_id}")
        IO.puts("📋 Poll: #{poll_id}")
        IO.puts("🎯 Option: #{option_id}")
        :ok
        
      {:error, :voter_already_voted} ->
        IO.puts("⚠️  #{voter_id} has already voted on this poll!")
        {:error, :voter_already_voted}
        
      {:error, :invalid_option} ->
        IO.puts("❌ Invalid option: #{option_id}")
        IO.puts("💡 Use option_1, option_2, option_3, etc.")
        {:error, :invalid_option}
        
      {:error, :poll_not_found} ->
        IO.puts("❌ Poll not found: #{poll_id}")
        {:error, :poll_not_found}
        
      {:error, reason} ->
        IO.puts("❌ Failed to cast vote: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Manually close a poll.
  
  ## Examples
  
      iex> close_poll("poll-123")
      :ok
      
      iex> close_poll("poll-123", "admin")
      :ok
  """
  def close_poll(poll_id, closer \\ "system") do
    command = %ClosePollCommand{
      poll_id: poll_id,
      closed_by: closer,
      reason: "Closed via REPL",
      requested_at: DateTime.utc_now()
    }
    
    case CommandedApp.dispatch(command) do
      :ok ->
        IO.puts("✅ Poll closed successfully!")
        IO.puts("📋 Poll: #{poll_id}")
        IO.puts("👤 Closed by: #{closer}")
        :ok
        
      {:error, reason} ->
        IO.puts("❌ Failed to close poll: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Manually start expiration countdown for a poll.
  
  ## Examples
  
      iex> start_countdown("poll-123", ~U[2024-12-31 23:59:59Z])
      :ok
  """
  def start_countdown(poll_id, expires_at) do
    command = %StartExpirationCountdownCommand{
      poll_id: poll_id,
      expires_at: expires_at,
      started_at: DateTime.utc_now()
    }
    
    case CommandedApp.dispatch(command) do
      :ok ->
        IO.puts("✅ Expiration countdown started!")
        IO.puts("📋 Poll: #{poll_id}")
        IO.puts("⏰ Expires at: #{Calendar.strftime(expires_at, "%Y-%m-%d %H:%M:%S UTC")}")
        :ok
        
      {:error, reason} ->
        IO.puts("❌ Failed to start countdown: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Manually expire a poll (simulates timer expiration).
  
  ## Examples
  
      iex> expire_poll("poll-123")
      :ok
  """
  def expire_poll(poll_id) do
    command = %ExpireCountdownCommand{
      poll_id: poll_id,
      expired_at: DateTime.utc_now()
    }
    
    case CommandedApp.dispatch(command) do
      :ok ->
        IO.puts("✅ Poll expired successfully!")
        IO.puts("📋 Poll: #{poll_id}")
        IO.puts("⏰ Expired at: #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")}")
        :ok
        
      {:error, reason} ->
        IO.puts("❌ Failed to expire poll: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Get poll results (placeholder - would need read-side implementation).
  
  ## Examples
  
      iex> results("poll-123")
      "📊 Results for poll-123 (read-side not implemented)"
  """
  def results(poll_id) do
    IO.puts("📊 Results for #{poll_id}")
    
    case SampleApp.Projections.get_poll_results(poll_id) do
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
  Lists polls created in this REPL session.
  
  ## Examples
  
      iex> list_polls()
      :ok
  """
  def list_polls do
    __init__()
    
    polls = :ets.tab2list(@polls_table)
    
    if polls == [] do
      IO.puts("📭 No polls created in this session yet.")
      IO.puts("💡 Create one with: create_poll(\"Title\", [\"Option1\", \"Option2\"])")
    else
      IO.puts("📋 Polls created in this session:")
      IO.puts("")
      
      polls
      |> Enum.sort_by(fn {_id, info} -> info.created_at end, DateTime)
      |> Enum.each(fn {poll_id, info} ->
        status = if info.expires_at && DateTime.compare(DateTime.utc_now(), info.expires_at) == :gt do
          "⏰ EXPIRED"
        else
          "✅ ACTIVE"
        end
        
        IO.puts("  🗳️  #{poll_id}")
        IO.puts("     📝 #{info.title}")
        IO.puts("     👤 Created by: #{info.creator}")
        IO.puts("     📅 Created: #{Calendar.strftime(info.created_at, "%H:%M:%S")}")
        if info.expires_at do
          IO.puts("     ⏰ Expires: #{Calendar.strftime(info.expires_at, "%H:%M:%S")}")
        end
        IO.puts("     📊 Status: #{status}")
        IO.puts("     🎯 Options: #{format_options_with_ids(info.options)}")
        IO.puts("")
      end)
    end
    
    :ok
  end
  
  @doc """
  Get detailed information about a specific poll.
  
  ## Examples
  
      iex> poll_info("poll-123")
      :ok
  """
  def poll_info(poll_id) do
    __init__()
    
    case :ets.lookup(@polls_table, poll_id) do
      [{^poll_id, info}] ->
        IO.puts("🗳️  Poll Information")
        IO.puts("=" |> String.duplicate(50))
        IO.puts("📋 ID: #{poll_id}")
        IO.puts("📝 Title: #{info.title}")
        IO.puts("👤 Creator: #{info.creator}")
        IO.puts("📅 Created: #{Calendar.strftime(info.created_at, "%Y-%m-%d %H:%M:%S UTC")}")
        
        if info.expires_at do
          status = if DateTime.compare(DateTime.utc_now(), info.expires_at) == :gt do
            "⏰ EXPIRED"
          else
            "✅ ACTIVE"
          end
          
          IO.puts("⏰ Expires: #{Calendar.strftime(info.expires_at, "%Y-%m-%d %H:%M:%S UTC")}")
          IO.puts("📊 Status: #{status}")
        else
          IO.puts("📊 Status: ✅ ACTIVE (no expiration)")
        end
        
        IO.puts("🎯 Options:")
        info.options
        |> Enum.with_index(1)
        |> Enum.each(fn {option, index} ->
          IO.puts("   option_#{index}: #{option}")
        end)
        
        IO.puts("")
        IO.puts("💡 Use these commands to interact:")
        IO.puts("   vote(\"#{poll_id}\", \"option_1\", \"your_name\")")
        IO.puts("   close_poll(\"#{poll_id}\")")
        :ok
        
      [] ->
        IO.puts("❌ Poll not found: #{poll_id}")
        IO.puts("💡 Use list_polls() to see available polls")
        {:error, :not_found}
    end
  end
  
  # Private helper functions
  
  defp display_poll_results(results) do
    IO.puts("")
    IO.puts("📊 Title: #{results.title}")
    IO.puts("🗳️  Total Votes: #{results.total_votes}")
    IO.puts("📊 Status: #{format_status(results.status)}")
    
    if results.closed_at do
      IO.puts("⏰ Closed: #{Calendar.strftime(results.closed_at, "%Y-%m-%d %H:%M:%S UTC")}")
    end
    
    if results.winner do
      IO.puts("🏆 Winner: #{results.winner.option_text} (#{results.winner.vote_count} votes, #{results.winner.percentage}%)")
    else
      case results.results do
        [] -> IO.puts("🤝 No votes yet")
        [first | rest] ->
          case Enum.find(rest, fn r -> r.vote_count == first.vote_count end) do
            nil -> IO.puts("🏆 Winner: #{first.option_text}")
            _ -> IO.puts("🤝 Tie for first place")
          end
      end
    end
    
    IO.puts("")
    IO.puts("📊 Results:")
    
    if results.results == [] do
      IO.puts("   No votes cast yet.")
    else
      results.results
      |> Enum.each(fn result ->
        bar = create_progress_bar(result.percentage)
        IO.puts("   #{result.rank}. #{result.option_text}")
        IO.puts("      #{result.vote_count} votes (#{result.percentage}%) #{bar}")
      end)
    end
    
    IO.puts("")
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
  
  defp generate_poll_id do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(999)
    "poll-#{timestamp}-#{random}"
  end
  
  defp store_poll_info(poll_id, title, options, creator, expires_at) do
    __init__()
    
    info = %{
      title: title,
      options: options,
      creator: creator,
      expires_at: expires_at,
      created_at: DateTime.utc_now()
    }
    
    :ets.insert(@polls_table, {poll_id, info})
  end
  
  defp format_options_with_ids(options) do
    options
    |> Enum.with_index(1)
    |> Enum.map(fn {option, index} -> "option_#{index}=#{option}" end)
    |> Enum.join(", ")
  end
end
