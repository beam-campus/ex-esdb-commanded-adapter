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
  
  ## Write Operations
  
  - `create_poll/3` - Create a new poll
  - `create_poll_with_expiration/4` - Create a poll that expires
  - `vote/3` - Cast a vote on a poll
  - `close_poll/2` - Manually close a poll
  - `start_countdown/2` - Start expiration countdown for a poll
  - `expire_poll/1` - Manually expire a poll
  - `bulk_create_polls/1` - Create multiple polls at once
  - `bulk_vote/1` - Cast multiple votes at once
  
  ## Read Operations
  
  - `results/1` - Get poll results
  - `list_active_polls/0` - List active polls
  - `list_closed_polls/0` - List closed polls
  - `list_all_polls/0` - List all polls
  - `voter_results/1` - Get voting history for a voter
  - `poll_details/1` - Get detailed poll information
  - `compare_poll_summary/1` - Compare poll summary (cache vs DB)
  - `compare_poll_results/1` - Compare poll results (cache vs DB)
  - `compare_voter_history/1` - Compare voter history (cache vs DB)
  
  ## Session Management
  
  - `list_polls/0` - List polls created in this session
  - `poll_info/1` - Get session info about a poll
  - `help/0` - Show available commands
  """
  
  alias SampleApp.VotingREPL.{Reader, Writer}
  
  require Logger
  
  def __init__ do
    Writer.__init__()
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
      
    📊 Poll Information (Cache):
      get_poll_summary_from_cache(poll_id)      # Get poll summary from cache
      list_all_poll_summaries_from_cache()      # List all poll summaries from cache
      list_active_polls_from_cache()            # List active polls from cache
      get_poll_results_from_cache(poll_id)      # Get poll results from cache
      get_voter_history_from_cache(voter_id)    # Get voter history from cache
      has_voter_voted_from_cache?(voter_id, poll_id)  # Check if voter voted (cache)

    📊 Poll Information (Database):
      get_poll_summary_from_db(poll_id)         # Get poll summary from database
      list_all_poll_summaries_from_db()         # List all poll summaries from database
      list_active_polls_from_db()               # List active polls from database
      get_poll_results_from_db(poll_id)         # Get poll results from database
      get_voter_history_from_db(voter_id)       # Get voter history from database
      has_voter_voted_from_db?(voter_id, poll_id)    # Check if voter voted (database)

    📊 Storage Comparison:
      compare_poll_summary(poll_id)       # Compare poll summary between cache and DB
      compare_poll_results(poll_id)       # Compare poll results between cache and DB
      compare_voter_history(voter_id)     # Compare voter history between cache and DB
      compare_all_poll_summaries()        # Compare all poll summaries
      compare_active_polls()              # Compare active polls list
      cache_stats()                       # Get cache statistics

    📊 Session Information:
      results(poll_id)              # Get poll results
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
  
  # Write operations - delegated to Writer module
  defdelegate create_poll(title, options, creator \\ "system"), to: Writer
  
  @doc """
  Creates a new poll with an expiration time.
  
  ## Examples
  
      iex> create_poll_with_expiration("Quick Vote", ["Yes", "No"], 3600)
      {:ok, "poll-1234567892"}
  """
  defdelegate create_poll_with_expiration(title, options, expires_in_seconds, creator \\ "system"), to: Writer
  
  @doc """
  Cast a vote on the specified poll.
  
  Use option IDs like "option_1", "option_2", etc.
  
  ## Examples
  
      iex> vote("poll-123", "option_1", "alice")
      :ok
      
      iex> vote("poll-123", "option_2", "bob")
      :ok
  """
  defdelegate vote(poll_id, option_id, voter_id), to: Writer
  
  @doc """
  Manually close a poll.
  
  ## Examples
  
      iex> close_poll("poll-123")
      :ok
      
      iex> close_poll("poll-123", "admin")
      :ok
  """
  defdelegate close_poll(poll_id, closer \\ "system"), to: Writer
  defdelegate start_countdown(poll_id, expires_at), to: Writer
  defdelegate expire_poll(poll_id), to: Writer
  defdelegate results(poll_id), to: Reader

  @doc """
  Lists all active polls from the database.

  ## Examples

      iex> list_active_polls()
      :ok
  """
  defdelegate list_active_polls(), to: Reader

  @doc """
  Gets poll results for all polls a voter has participated in.

  ## Examples

      iex> voter_results("alice")
      :ok
  """
  defdelegate voter_results(voter_id), to: Reader

  @doc """
  Lists results for all closed polls.

  ## Examples

      iex> list_closed_polls()
      :ok
  """
  defdelegate list_closed_polls(), to: Reader

  @doc """
  Lists all polls from the database.

  ## Examples

      iex> list_all_polls()
      :ok
  """
  defdelegate list_all_polls(), to: Reader

  @doc """
  Compare poll summary between cache and database.

  ## Examples

      iex> compare_poll_summary("poll-123")
      :ok
  """
  defdelegate compare_poll_summary(poll_id), to: Reader

  @doc """
  Compare poll results between cache and database.

  ## Examples

      iex> compare_poll_results("poll-123")
      :ok
  """
  defdelegate compare_poll_results(poll_id), to: Reader

  @doc """
  Compare voter history between cache and database.

  ## Examples

      iex> compare_voter_history("alice")
      :ok
  """
  defdelegate compare_voter_history(voter_id), to: Reader

  @doc """
  Compare all poll summaries between cache and database.

  ## Examples

      iex> compare_all_poll_summaries()
      :ok
  """
  defdelegate compare_all_poll_summaries(), to: Reader

  @doc """
  Compare active polls between cache and database.

  ## Examples

      iex> compare_active_polls()
      :ok
  """
  defdelegate compare_active_polls(), to: Reader

  @doc """
  Get cache statistics including total polls, active polls, etc.

  ## Examples

      iex> cache_stats()
      :ok
  """
  defdelegate cache_stats(), to: Reader
  defdelegate list_polls(), to: Writer
  defdelegate poll_info(poll_id), to: Writer

  @doc """
  Generate example data using predefined poll templates.
  You can specify how many polls to create and how many votes per poll.

  ## Examples
      # Create 3 polls with 10 votes each
      iex> generate_example_data(3, 10)
      :ok
  """
  def generate_example_data(poll_count \\ 5, votes_per_poll \\ 10) do
    alias SampleApp.TestDataGenerator, as: TestGen

    IO.puts("🚀 Generating example data...")
    IO.puts("📋 Creating #{poll_count} polls with #{votes_per_poll} votes each")

    result = TestGen.generate_random_polls_with_votes(poll_count, votes_per_poll)

    IO.puts("\n✅ Example data generated successfully!")
    IO.puts("   #{length(result.poll_ids)} polls created")
    IO.puts("   #{poll_count * votes_per_poll} total votes cast")
    IO.puts("\n💡 Try these commands to explore the data:")
    IO.puts("   list_all_polls()        - See all polls")
    IO.puts("   list_active_polls()      - See active polls")
    IO.puts("   results(\"#{hd(result.poll_ids)}\")  - See results for first poll")
    :ok
  end

  @doc """
  Generate data for load testing.
  Creates many polls and votes to test system performance.

  ## Examples
      # Create 100 polls with 1000 votes each
      iex> generate_load_test_data(100, 1000)
      :ok
  """
  def generate_load_test_data(poll_count \\ 100, votes_per_poll \\ 1000) do
    alias SampleApp.TestDataGenerator, as: TestGen

    IO.puts("🏋️ Starting load test data generation...")
    IO.puts("📊 Target: #{poll_count} polls with #{votes_per_poll} votes each")
    IO.puts("💭 This might take a while...\n")

    start_time = System.monotonic_time()

    # Generate data in smaller batches to show progress
    poll_batch_size = 10
    total_batches = ceil(poll_count / poll_batch_size)

    1..total_batches
    |> Enum.reduce([], fn _batch_num, acc_poll_ids ->
      remaining_polls = min(poll_batch_size, poll_count - length(acc_poll_ids))
      result = TestGen.generate_random_polls_with_votes(remaining_polls, votes_per_poll)

      progress = length(acc_poll_ids) + remaining_polls
      percentage = Float.round(progress / poll_count * 100, 1)
      IO.puts("   Progress: #{progress}/#{poll_count} polls (#{percentage}%)")

      acc_poll_ids ++ result.poll_ids
    end)

    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    duration_seconds = duration / 1000

    total_operations = poll_count * (votes_per_poll + 1) # +1 for poll creation
    ops_per_second = Float.round(total_operations / duration_seconds, 1)

    IO.puts("\n✅ Load test data generation complete!")
    IO.puts("⏱️  Time taken: #{Float.round(duration_seconds, 1)} seconds")
    IO.puts("📊 Statistics:")
    IO.puts("   - #{poll_count} polls created")
    IO.puts("   - #{poll_count * votes_per_poll} votes cast")
    IO.puts("   - #{total_operations} total operations")
    IO.puts("   - #{ops_per_second} operations per second")

    IO.puts("\n💡 Try these commands to verify:")
    IO.puts("   list_all_polls()         - See all polls")
    IO.puts("   cache_stats()            - View cache statistics")
    IO.puts("   compare_active_polls()   - Compare cache vs database")
    :ok
  end

  @doc """
  Generate test scenarios that cover all system behaviors.
  Creates polls in various states (active, closed, expired) with different voting patterns.

  ## Examples
      iex generate_test_scenarios()
      :ok
  """
  def generate_test_scenarios do
    alias SampleApp.TestDataGenerator, as: TestGen

    IO.puts("🧪 Generating test scenarios...\n")

    # 1. Active polls with votes
    IO.puts("1️⃣  Creating active polls with votes...")
    {:ok, active_poll_1} = create_poll("Active Poll: High Activity", ["Yes", "No", "Maybe"])
    {:ok, active_poll_2} = create_poll("Active Poll: Low Activity", ["Red", "Blue", "Green"])
    
    # Generate some votes for active polls
    TestGen.generate_random_votes(active_poll_1, 20)
    TestGen.generate_random_votes(active_poll_2, 5)

    # 2. Expired polls
    IO.puts("\n2️⃣  Creating expired polls...")
    {:ok, expired_poll} = create_poll_with_expiration("Expired Poll", ["Option A", "Option B"], 1)
    Process.sleep(1500) # Wait for expiration
    TestGen.generate_random_votes(expired_poll, 10)

    # 3. Manually closed polls
    IO.puts("\n3️⃣  Creating and closing polls...")
    {:ok, closed_poll} = create_poll("Closed Poll", ["First", "Second", "Third"])
    TestGen.generate_random_votes(closed_poll, 15)
    close_poll(closed_poll)

    # 4. Poll with tied results
    IO.puts("\n4️⃣  Creating poll with tied votes...")
    {:ok, tied_poll} = create_poll("Tied Poll", ["Left", "Right"])
    vote(tied_poll, "option_1", "voter1")
    vote(tied_poll, "option_2", "voter2")

    # 5. Poll with no votes
    IO.puts("\n5️⃣  Creating poll with no votes...")
    {:ok, _empty_poll} = create_poll("Empty Poll", ["Choice A", "Choice B"])

    # Summary
    IO.puts("\n✅ Test scenarios generated successfully!")
    IO.puts("Created various poll types:")
    IO.puts("  - Active polls (high and low activity)")
    IO.puts("  - Expired poll")
    IO.puts("  - Manually closed poll")
    IO.puts("  - Poll with tied votes")
    IO.puts("  - Poll with no votes")

    IO.puts("\n💡 Try these commands to explore:")
    IO.puts("   list_all_polls()          - See all generated polls")
    IO.puts("   results(\"#{active_poll_1}\")   - View high activity poll")
    IO.puts("   results(\"#{tied_poll}\")      - View tied poll results")
    IO.puts("   compare_poll_results(\"#{closed_poll}\") - Compare closed poll results")
    :ok
  end
end
