defmodule SampleApp.TestHelpers do
  @moduledoc """
  Test helpers for SampleApp tests.
  
  Provides utilities for cache management, test data generation,
  and common test scenarios.
  """
  
  @doc """
  Ensures a Cachex cache exists for testing.
  Creates the cache if it doesn't exist, or clears it if it does.
  """
  def ensure_test_cache(cache_name) do
    case Cachex.exists?(cache_name) do
      {:ok, true} ->
        # Cache exists, clear it
        case Cachex.clear(cache_name) do
          {:ok, _count} -> :ok
          {:error, reason} -> {:error, {:clear_failed, reason}}
        end
        
      {:ok, false} ->
        # Cache doesn't exist, create it
        case Cachex.start_link(cache_name, []) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> 
            # Race condition - cache was created by another process
            # Clear it to ensure clean state
            Cachex.clear(cache_name)
            :ok
          {:error, reason} -> {:error, {:start_failed, reason}}
        end
        
      {:error, reason} ->
        # Error checking existence, try to create anyway
        case Cachex.start_link(cache_name, []) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> 
            Cachex.clear(cache_name)
            :ok
          {:error, create_reason} -> {:error, {:existence_check_failed, reason, create_reason}}
        end
    end
  end
  
  @doc """
  Safely stops a Cachex cache for testing.
  Does nothing if the cache doesn't exist.
  """
  def stop_test_cache(cache_name) do
    case Cachex.exists?(cache_name) do
      {:ok, true} ->
        case Process.whereis(cache_name) do
          pid when is_pid(pid) ->
            Process.exit(pid, :normal)
            # Wait a bit for the process to die
            :timer.sleep(10)
            :ok
          nil ->
            :ok
        end
      _ ->
        :ok
    end
  end
  
  @doc """
  Generates a unique poll ID for testing.
  """
  def unique_poll_id(prefix \\ "test-poll") do
    timestamp = System.unique_integer([:positive])
    random = :rand.uniform(1000)
    "#{prefix}-#{timestamp}-#{random}"
  end
  
  @doc """
  Generates a unique voter ID for testing.
  """
  def unique_voter_id(prefix \\ "voter") do
    timestamp = System.unique_integer([:positive])
    random = :rand.uniform(1000)
    "#{prefix}-#{timestamp}-#{random}"
  end
  
  @doc """
  Creates test poll options.
  """
  def test_poll_options(count \\ 3) do
    1..count
    |> Enum.map(&"Option #{&1}")
  end
  
  @doc """
  Waits for a projection to complete by polling the cache.
  Returns :ok when the expected data is found, or :timeout after max_wait_ms.
  """
  def wait_for_projection(cache_name, key, expected_fn, max_wait_ms \\ 5000) do
    wait_for_projection(cache_name, key, expected_fn, max_wait_ms, 0)
  end
  
  defp wait_for_projection(_cache_name, _key, _expected_fn, max_wait_ms, elapsed_ms) when elapsed_ms >= max_wait_ms do
    :timeout
  end
  
  defp wait_for_projection(cache_name, key, expected_fn, max_wait_ms, elapsed_ms) do
    case Cachex.get(cache_name, key) do
      {:ok, value} when value != nil ->
        if expected_fn.(value) do
          :ok
        else
          :timer.sleep(10)
          wait_for_projection(cache_name, key, expected_fn, max_wait_ms, elapsed_ms + 10)
        end
      
      _ ->
        :timer.sleep(10)
        wait_for_projection(cache_name, key, expected_fn, max_wait_ms, elapsed_ms + 10)
    end
  end
  
  @doc """
  Waits for multiple projections to complete.
  """
  def wait_for_projections(projections, max_wait_ms \\ 5000) do
    tasks = Enum.map(projections, fn {cache_name, key, expected_fn} ->
      Task.async(fn ->
        wait_for_projection(cache_name, key, expected_fn, max_wait_ms)
      end)
    end)
    
    results = Task.await_many(tasks, max_wait_ms + 1000)
    
    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, :projection_timeout, results}
    end
  end
  
  @doc """
  Creates a complete test scenario with poll initialization and votes.
  Returns {poll_id, vote_results}.
  """
  def create_test_poll_with_votes(poll_options \\ ["Option A", "Option B"], voters \\ ["alice", "bob"]) do
    poll_id = unique_poll_id()
    
    # Initialize poll
    init_command = %SampleApp.Domain.InitializePoll.CommandV1{
      poll_id: poll_id,
      title: "Test Poll",
      description: "A test poll for automated testing",
      options: poll_options,
      created_by: "test-creator",
      expires_at: nil,
      requested_at: DateTime.utc_now()
    }
    
    case SampleApp.CommandedApp.dispatch(init_command) do
      :ok ->
        # Cast votes
        vote_results = Enum.with_index(voters, fn voter, index ->
          option_index = rem(index, length(poll_options)) + 1
          
          vote_command = %SampleApp.Domain.CastVote.CommandV1{
            poll_id: poll_id,
            option_id: "option_#{option_index}",
            voter_id: voter,
            requested_at: DateTime.utc_now()
          }
          
          {voter, SampleApp.CommandedApp.dispatch(vote_command)}
        end)
        
        {:ok, poll_id, vote_results}
      
      error ->
        {:error, :poll_init_failed, error}
    end
  end
  
  @doc """
  Asserts that a cache contains expected data.
  """
  def assert_cache_contains(cache_name, key, assertion_fn) do
    case Cachex.get(cache_name, key) do
      {:ok, value} when value != nil ->
        assertion_fn.(value)
      
      {:ok, nil} ->
        raise "Expected data in cache #{cache_name} for key #{key}, but found nil"
      
      {:error, reason} ->
        raise "Failed to read from cache #{cache_name}: #{inspect(reason)}"
    end
  end
  
  @doc """
  Measures execution time of a function in milliseconds.
  """
  def measure_time(fun) do
    {time_microseconds, result} = :timer.tc(fun)
    time_milliseconds = time_microseconds / 1000
    {time_milliseconds, result}
  end
  
  @doc """
  Runs a function with timeout and returns result or :timeout.
  """
  def with_timeout(fun, timeout_ms \\ 5000) do
    task = Task.async(fun)
    
    try do
      Task.await(task, timeout_ms)
    catch
      :exit, {:timeout, _} -> :timeout
    end
  end
  
  @doc """
  Generates test data for property-based testing.
  """
  def generate_test_voters(count) when count > 0 do
    1..count
    |> Enum.map(&"test-voter-#{&1}")
  end
  
  def generate_test_options(count) when count > 0 do
    1..count
    |> Enum.map(&"Test Option #{&1}")
  end
  
  @doc """
  Sets up clean test environment for integration tests.
  """
  def setup_integration_test do
    # Ensure all test caches are clean
    test_caches = [:poll_summaries, :poll_results, :voter_history]
    
    Enum.each(test_caches, fn cache_name ->
      ensure_test_cache(cache_name)
    end)
    
    # Return cleanup function
    fn ->
      Enum.each(test_caches, &stop_test_cache/1)
    end
  end
  
  @doc """
  Validates the consistency of read models after operations.
  """
  def validate_read_model_consistency(poll_id) do
    with {:ok, summary} <- Cachex.get(:poll_summaries, poll_id),
         {:ok, results} <- Cachex.get(:poll_results, poll_id) do
      
      # Check that totals match
      if summary.total_votes != results.total_votes do
        {:error, :total_votes_mismatch, summary.total_votes, results.total_votes}
      else
        # Check that vote counts are consistent
        derived_counts = 
          results.votes
          |> Map.values()
          |> Enum.frequencies()
        
        summary_counts = 
          summary.vote_counts
          |> Enum.filter(fn {_option, count} -> count > 0 end)
          |> Map.new()
        
        if derived_counts == summary_counts do
          :ok
        else
          {:error, :vote_counts_mismatch, derived_counts, summary_counts}
        end
      end
      
    else
      error -> {:error, :cache_read_failed, error}
    end
  end
  
  @doc """
  Creates a mock event for testing event handlers.
  """
  def mock_initialize_poll_event(overrides \\ %{}) do
    defaults = %{
      poll_id: unique_poll_id(),
      title: "Mock Poll",
      description: "A poll for testing",
      options: [
        %{id: "option_1", text: "Option 1"},
        %{id: "option_2", text: "Option 2"}
      ],
      created_by: "test-creator",
      expires_at: nil,
      initialized_at: DateTime.utc_now(),
      version: 1
    }
    
    struct(SampleApp.Domain.InitializePoll.EventV1, Map.merge(defaults, overrides))
  end
  
  def mock_cast_vote_event(overrides \\ %{}) do
    defaults = %{
      poll_id: unique_poll_id(),
      option_id: "option_1",
      voter_id: unique_voter_id(),
      casted_at: DateTime.utc_now(),
      version: 1
    }
    
    struct(SampleApp.Domain.CastVote.EventV1, Map.merge(defaults, overrides))
  end
end
