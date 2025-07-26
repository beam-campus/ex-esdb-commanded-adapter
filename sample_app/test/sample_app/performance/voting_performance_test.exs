defmodule SampleApp.Performance.VotingPerformanceTest do
  use ExUnit.Case, async: false
  
  alias SampleApp.CommandedApp
  alias SampleApp.Domain.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.Domain.CastVote.CommandV1, as: CastVoteCommand
  
  @moduletag :performance
  @moduletag timeout: 60_000  # Allow longer timeout for performance tests
  
  describe "Voting system performance benchmarks" do
    setup do
      cleanup_cache()
      
      on_exit(fn ->
        cleanup_cache()
      end)
      
      :ok
    end
    
    test "benchmark poll initialization" do
      poll_count = 100
      
      {time_microseconds, results} = :timer.tc(fn ->
        1..poll_count
        |> Enum.map(fn i ->
          poll_id = "perf-init-poll-#{i}"
          
          command = %InitializePollCommand{
            poll_id: poll_id,
            title: "Performance Test Poll #{i}",
            description: "Benchmarking poll initialization",
            options: ["Option A", "Option B", "Option C"],
            created_by: "perf-tester",
            expires_at: nil,
            requested_at: DateTime.utc_now()
          }
          
          CommandedApp.dispatch(command)
        end)
      end)
      
      # All dispatches should succeed
      assert Enum.all?(results, &(&1 == :ok))
      
      # Calculate performance metrics
      total_time_ms = time_microseconds / 1000
      avg_time_per_poll = total_time_ms / poll_count
      throughput_per_sec = poll_count / (total_time_ms / 1000)
      
      IO.puts("\n=== Poll Initialization Performance ===")
      IO.puts("Total polls: #{poll_count}")
      IO.puts("Total time: #{Float.round(total_time_ms, 2)} ms")
      IO.puts("Average per poll: #{Float.round(avg_time_per_poll, 2)} ms")
      IO.puts("Throughput: #{Float.round(throughput_per_sec, 2)} polls/sec")
      
      # Performance assertions (adjust thresholds as needed)
      assert avg_time_per_poll < 50.0  # Less than 50ms per poll
      assert throughput_per_sec > 10.0  # More than 10 polls per second
    end
    
    test "benchmark sequential voting" do
      poll_id = "perf-sequential-poll"
      vote_count = 500
      
      # Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Sequential Voting Performance Test",
        description: "Benchmarking sequential vote processing",
        options: Enum.map(1..10, &"Option #{&1}"),
        created_by: "perf-tester",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      :timer.sleep(100)  # Let initialization complete
      
      # Generate vote commands
      vote_commands = Enum.map(1..vote_count, fn i ->
        %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_#{rem(i, 10) + 1}",
          voter_id: "voter_#{i}",
          requested_at: DateTime.utc_now()
        }
      end)
      
      # Benchmark sequential voting
      {time_microseconds, results} = :timer.tc(fn ->
        Enum.map(vote_commands, &CommandedApp.dispatch/1)
      end)
      
      # All votes should succeed
      assert Enum.all?(results, &(&1 == :ok))
      
      # Wait for projections to complete
      :timer.sleep(1000)
      
      # Verify final state
      {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
      assert summary.total_votes == vote_count
      
      # Calculate metrics
      total_time_ms = time_microseconds / 1000
      avg_time_per_vote = total_time_ms / vote_count
      throughput_per_sec = vote_count / (total_time_ms / 1000)
      
      IO.puts("\n=== Sequential Voting Performance ===")
      IO.puts("Total votes: #{vote_count}")
      IO.puts("Total time: #{Float.round(total_time_ms, 2)} ms")
      IO.puts("Average per vote: #{Float.round(avg_time_per_vote, 2)} ms")
      IO.puts("Throughput: #{Float.round(throughput_per_sec, 2)} votes/sec")
      
      # Performance assertions
      assert avg_time_per_vote < 20.0  # Less than 20ms per vote
      assert throughput_per_sec > 25.0  # More than 25 votes per second
    end
    
    test "benchmark concurrent voting" do
      poll_id = "perf-concurrent-poll"
      vote_count = 200
      concurrency = 20  # Number of concurrent tasks
      
      # Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Concurrent Voting Performance Test",
        description: "Benchmarking concurrent vote processing",
        options: Enum.map(1..5, &"Option #{&1}"),
        created_by: "perf-tester",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      :timer.sleep(100)
      
      # Benchmark concurrent voting
      {time_microseconds, _results} = :timer.tc(fn ->
        1..vote_count
        |> Enum.chunk_every(div(vote_count, concurrency))
        |> Enum.map(fn batch ->
          Task.async(fn ->
            Enum.map(batch, fn i ->
              command = %CastVoteCommand{
                poll_id: poll_id,
                option_id: "option_#{rem(i, 5) + 1}",
                voter_id: "concurrent_voter_#{i}",
                requested_at: DateTime.utc_now()
              }
              
              CommandedApp.dispatch(command)
            end)
          end)
        end)
        |> Task.await_many(30_000)
      end)
      
      # Wait for projections
      :timer.sleep(1000)
      
      # Verify final state
      {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
      assert summary.total_votes == vote_count
      
      # Calculate metrics
      total_time_ms = time_microseconds / 1000
      avg_time_per_vote = total_time_ms / vote_count
      throughput_per_sec = vote_count / (total_time_ms / 1000)
      
      IO.puts("\n=== Concurrent Voting Performance ===")
      IO.puts("Total votes: #{vote_count}")
      IO.puts("Concurrency: #{concurrency} tasks")
      IO.puts("Total time: #{Float.round(total_time_ms, 2)} ms")
      IO.puts("Average per vote: #{Float.round(avg_time_per_vote, 2)} ms")
      IO.puts("Throughput: #{Float.round(throughput_per_sec, 2)} votes/sec")
      
      # Concurrent performance should be better than sequential
      assert throughput_per_sec > 50.0  # Should be much faster with concurrency
    end
    
    test "benchmark projection processing latency" do
      poll_id = "perf-projection-poll"
      
      # Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Projection Latency Test",
        description: "Measuring projection processing speed",
        options: ["Option A", "Option B"],
        created_by: "perf-tester",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      
      # Measure time from command dispatch to projection completion
      measurements = Enum.map(1..50, fn i ->
        voter_id = "latency_voter_#{i}"
        
        # Record start time
        start_time = System.monotonic_time(:microsecond)
        
        # Dispatch vote
        vote_command = %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_#{rem(i, 2) + 1}",
          voter_id: voter_id,
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(vote_command)
        
        # Poll for projection completion
        end_time = wait_for_projection_update(poll_id, voter_id, start_time)
        
        end_time - start_time
      end)
      
      # Calculate latency statistics
      avg_latency = Enum.sum(measurements) / length(measurements)
      min_latency = Enum.min(measurements)
      max_latency = Enum.max(measurements)
      p95_latency = percentile(measurements, 0.95)
      
      # Convert to milliseconds
      avg_latency_ms = avg_latency / 1000
      min_latency_ms = min_latency / 1000
      max_latency_ms = max_latency / 1000
      p95_latency_ms = p95_latency / 1000
      
      IO.puts("\n=== Projection Processing Latency ===")
      IO.puts("Samples: #{length(measurements)}")
      IO.puts("Average latency: #{Float.round(avg_latency_ms, 2)} ms")
      IO.puts("Min latency: #{Float.round(min_latency_ms, 2)} ms")
      IO.puts("Max latency: #{Float.round(max_latency_ms, 2)} ms")
      IO.puts("95th percentile: #{Float.round(p95_latency_ms, 2)} ms")
      
      # Latency assertions
      assert avg_latency_ms < 100.0  # Average under 100ms
      assert p95_latency_ms < 200.0  # 95th percentile under 200ms
    end
    
    test "benchmark memory usage during high load" do
      poll_id = "perf-memory-poll"
      vote_count = 1000
      
      # Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Memory Usage Test",
        description: "Monitoring memory during high load",
        options: Enum.map(1..20, &"Option #{&1}"),
        created_by: "perf-tester",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      :timer.sleep(100)
      
      # Measure initial memory
      initial_memory = :erlang.memory(:total)
      
      # Generate high load
      {time_microseconds, _results} = :timer.tc(fn ->
        1..vote_count
        |> Task.async_stream(fn i ->
          command = %CastVoteCommand{
            poll_id: poll_id,
            option_id: "option_#{rem(i, 20) + 1}",
            voter_id: "memory_voter_#{i}",
            requested_at: DateTime.utc_now()
          }
          
          CommandedApp.dispatch(command)
        end, max_concurrency: 50, timeout: 30_000)
        |> Enum.to_list()
      end)
      
      # Wait for projections and GC
      :timer.sleep(2000)
      :erlang.garbage_collect()
      
      # Measure final memory
      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory
      memory_per_vote = memory_increase / vote_count
      
      # Verify final state
      {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
      assert summary.total_votes == vote_count
      
      total_time_ms = time_microseconds / 1000
      throughput = vote_count / (total_time_ms / 1000)
      
      IO.puts("\n=== Memory Usage Performance ===")
      IO.puts("Total votes: #{vote_count}")
      IO.puts("Total time: #{Float.round(total_time_ms, 2)} ms")
      IO.puts("Throughput: #{Float.round(throughput, 2)} votes/sec")
      IO.puts("Initial memory: #{format_bytes(initial_memory)}")
      IO.puts("Final memory: #{format_bytes(final_memory)}")
      IO.puts("Memory increase: #{format_bytes(memory_increase)}")
      IO.puts("Memory per vote: #{format_bytes(memory_per_vote)}")
      
      # Memory efficiency assertions
      assert memory_per_vote < 1000  # Less than 1KB per vote
      assert memory_increase < 50_000_000  # Less than 50MB total increase
    end
  end
  
  # Helper functions
  
  defp wait_for_projection_update(poll_id, voter_id, start_time, max_wait \\ 5000) do
    wait_for_projection_update(poll_id, voter_id, start_time, max_wait, 0)
  end
  
  defp wait_for_projection_update(poll_id, voter_id, start_time, max_wait, elapsed) when elapsed >= max_wait do
    # Timeout - return current time
    System.monotonic_time(:microsecond)
  end
  
  defp wait_for_projection_update(poll_id, voter_id, start_time, max_wait, elapsed) do
    case Cachex.get(:poll_results, poll_id) do
      {:ok, results} when is_map(results) ->
        if Map.has_key?(results.votes, voter_id) do
          System.monotonic_time(:microsecond)
        else
          :timer.sleep(1)
          wait_for_projection_update(poll_id, voter_id, start_time, max_wait, elapsed + 1)
        end
      
      _ ->
        :timer.sleep(1)
        wait_for_projection_update(poll_id, voter_id, start_time, max_wait, elapsed + 1)
    end
  end
  
  defp percentile(list, p) when p >= 0 and p <= 1 do
    sorted = Enum.sort(list)
    index = trunc(p * (length(sorted) - 1))
    Enum.at(sorted, index)
  end
  
  defp format_bytes(bytes) when bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 2)} MB"
  end
  
  defp format_bytes(bytes) when bytes >= 1_000 do
    "#{Float.round(bytes / 1_000, 2)} KB"
  end
  
  defp format_bytes(bytes) do
    "#{bytes} bytes"
  end
  
  defp cleanup_cache do
    safe_clear_cache(:poll_summaries)
    safe_clear_cache(:poll_results)
    safe_clear_cache(:voter_history)
  end
  
  defp safe_clear_cache(cache_name) do
    try do
      case Cachex.clear(cache_name) do
        {:ok, _} -> :ok
        {:error, :no_cache} -> :ok
        _ -> :ok
      end
    rescue
      _ -> :ok
    end
  end
end
