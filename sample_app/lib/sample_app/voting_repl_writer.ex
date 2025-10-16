defmodule SampleApp.VotingREPL.Writer do
  @moduledoc """
  Write-side operations for the VotingREPL interface.
  Handles all command operations like creating polls, voting, closing polls, etc.
  """

  alias SampleApp.CommandedApp
  alias SampleApp.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.CastVote.CommandV1, as: CastVoteCommand
  alias SampleApp.ClosePoll.CommandV1, as: ClosePollCommand
  alias SampleApp.ExpireCountdown.CommandV1, as: ExpireCountdownCommand
  alias SampleApp.StartExpirationCountdown.CommandV1, as: StartExpirationCountdownCommand

  # Track polls created in this session
  @polls_table :voting_repl_polls

  def __init__ do
    # Initialize ETS table for tracking polls if it doesn't exist
    unless :ets.whereis(@polls_table) != :undefined do
      :ets.new(@polls_table, [:set, :public, :named_table])
    end
  end

  @doc """
  Creates a new poll with the given title and options.

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
      options: options |> Enum.with_index(1) |> Enum.map(fn {text, index} -> %{id: "option_#{index}", text: text} end),
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
      options: options |> Enum.with_index(1) |> Enum.map(fn {text, index} -> %{id: "option_#{index}", text: text} end),
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
  Create multiple polls with the given list of titles and options.

  ## Examples

      iex> bulk_create_polls([
        {"Favorite Color?", ["Red", "Blue", "Green"]},
        {"Best Framework?", ["Phoenix", "Rails", "Django"]}
      ])
      :ok
  """
  def bulk_create_polls(polls) do
    results = Enum.map(polls, fn {title, options} ->
      case create_poll(title, options) do
        {:ok, poll_id} -> {:ok, {title, poll_id}}
        {:error, reason} -> {:error, {title, reason}}
      end
    end)
    
    {successes, failures} = Enum.split_with(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
    
    success_count = length(successes)
    failure_count = length(failures)
    
    IO.puts("📋 Bulk Poll Creation Summary:")
    IO.puts("✅ Successfully created: #{success_count} polls")
    
    unless failures == [] do
      IO.puts("❌ Failed to create: #{failure_count} polls")
      IO.puts("\nFailures:")
      Enum.each(failures, fn {:error, {title, reason}} ->
        IO.puts("   #{title}: #{inspect(reason)}")
      end)
    end
    
    :ok
  end

  @doc """
  Cast votes in bulk on multiple polls.

  ## Examples

      iex> bulk_vote([
        {"poll-123", "option_1", "alice"},
        {"poll-123", "option_2", "bob"}
      ])
      :ok
  """
  def bulk_vote(votes) do
    results = Enum.map(votes, fn {poll_id, option_id, voter_id} ->
      case vote(poll_id, option_id, voter_id) do
        :ok -> {:ok, {poll_id, voter_id}}
        {:error, reason} -> {:error, {poll_id, voter_id, reason}}
      end
    end)
    
    {successes, failures} = Enum.split_with(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
    
    success_count = length(successes)
    failure_count = length(failures)
    
    IO.puts("📋 Bulk Voting Summary:")
    IO.puts("✅ Successfully cast: #{success_count} votes")
    
    unless failures == [] do
      IO.puts("❌ Failed to cast: #{failure_count} votes")
      IO.puts("\nFailures:")
      Enum.each(failures, fn {:error, {poll_id, voter_id, reason}} ->
        IO.puts("   Poll #{poll_id}, Voter #{voter_id}: #{inspect(reason)}")
      end)
    end
    
    :ok
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
