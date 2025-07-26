defmodule SampleApp.Integration.VotingSystemIntegrationTest do
  use ExUnit.Case, async: false  # Integration tests should not be async
  
  alias SampleApp.CommandedApp
  alias SampleApp.Domain.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.Domain.CastVote.CommandV1, as: CastVoteCommand
  alias SampleApp.Domain.ClosePoll.CommandV1, as: ClosePollCommand
  alias SampleApp.ReadModels.{PollSummary, PollResults}
  
  @moduletag :integration
  
  describe "Complete voting system integration" do
    setup do
      # Ensure clean state for each test
      cleanup_cache()
      
      on_exit(fn ->
        cleanup_cache()
      end)
      
      :ok
    end
    
    test "end-to-end poll lifecycle from creation to closure" do
      poll_id = "e2e-poll-#{System.unique_integer([:positive])}"
      
      # 1. Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Integration Test Poll",
        description: "Testing complete poll lifecycle",
        options: ["Option A", "Option B", "Option C"],
        created_by: "test-creator",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      
      # Wait for projections to process
      :timer.sleep(100)
      
      # Verify poll summary was created
      {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
      assert summary != nil
      assert summary.poll_id == poll_id
      assert summary.title == "Integration Test Poll"
      assert summary.total_votes == 0
      assert summary.status == :active
      
      # Verify poll results were initialized
      {:ok, results} = Cachex.get(:poll_results, poll_id)
      assert results != nil
      assert results.poll_id == poll_id
      assert results.total_votes == 0
      
      # 2. Cast multiple votes
      vote_commands = [
        %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_1",
          voter_id: "alice",
          requested_at: DateTime.utc_now()
        },
        %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_2", 
          voter_id: "bob",
          requested_at: DateTime.utc_now()
        },
        %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_1",
          voter_id: "charlie",
          requested_at: DateTime.utc_now()
        },
        %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_3",
          voter_id: "diana",
          requested_at: DateTime.utc_now()
        }
      ]
      
      # Dispatch all vote commands
      Enum.each(vote_commands, fn command ->
        assert :ok = CommandedApp.dispatch(command)
      end)
      
      # Wait for projections to process votes
      :timer.sleep(200)
      
      # 3. Verify vote counts in both read models
      {:ok, updated_summary} = Cachex.get(:poll_summaries, poll_id)
      assert updated_summary.total_votes == 4
      assert updated_summary.vote_counts["option_1"] == 2
      assert updated_summary.vote_counts["option_2"] == 1
      assert updated_summary.vote_counts["option_3"] == 1
      
      {:ok, updated_results} = Cachex.get(:poll_results, poll_id)
      assert updated_results.total_votes == 4
      assert updated_results.votes["alice"] == "option_1"
      assert updated_results.votes["bob"] == "option_2"
      assert updated_results.votes["charlie"] == "option_1"
      assert updated_results.votes["diana"] == "option_3"
      
      # 4. Attempt duplicate vote (should be rejected)
      duplicate_vote = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_2",
        voter_id: "alice",  # Alice already voted
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, :voter_has_already_voted} = CommandedApp.dispatch(duplicate_vote)
      
      # Verify vote counts didn't change
      :timer.sleep(100)
      {:ok, unchanged_summary} = Cachex.get(:poll_summaries, poll_id)
      assert unchanged_summary.total_votes == 4
      
      # 5. Close the poll
      close_command = %ClosePollCommand{
        poll_id: poll_id,
        closed_by: "test-creator",
        reason: "Testing completed",
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(close_command)
      
      # Wait for projections to process closure
      :timer.sleep(100)
      
      # 6. Verify poll is closed
      {:ok, closed_summary} = Cachex.get(:poll_summaries, poll_id)
      assert closed_summary.status == :closed
      assert closed_summary.closed_at != nil
      
      # 7. Attempt vote on closed poll (should be rejected)
      vote_on_closed = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_1",
        voter_id: "eve",
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, :poll_not_active} = CommandedApp.dispatch(vote_on_closed)
    end
    
    test "concurrent voting stress test" do
      poll_id = "stress-poll-#{System.unique_integer([:positive])}"
      
      # Initialize poll with many options
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Stress Test Poll",
        description: "Testing concurrent voting",
        options: Enum.map(1..10, &"Option #{&1}"),
        created_by: "test-creator",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      :timer.sleep(100)
      
      # Generate many concurrent votes
      vote_tasks = Enum.map(1..50, fn i ->
        Task.async(fn ->
          option_id = "option_#{rem(i, 10) + 1}"
          voter_id = "voter_#{i}"
          
          command = %CastVoteCommand{
            poll_id: poll_id,
            option_id: option_id,
            voter_id: voter_id,
            requested_at: DateTime.utc_now()
          }
          
          CommandedApp.dispatch(command)
        end)
      end)
      
      # Wait for all votes to complete
      results = Task.await_many(vote_tasks, 10_000)
      successful_votes = Enum.count(results, &(&1 == :ok))
      
      # Should have 50 successful votes (no duplicates)
      assert successful_votes == 50
      
      # Wait for projections to catch up
      :timer.sleep(500)
      
      # Verify final counts
      {:ok, final_summary} = Cachex.get(:poll_summaries, poll_id)
      assert final_summary.total_votes == 50
      
      # Verify vote distribution across options
      vote_counts = final_summary.vote_counts
      total_distributed = vote_counts |> Map.values() |> Enum.sum()
      assert total_distributed == 50
      
      # Each option should have approximately 5 votes (50/10)
      Enum.each(vote_counts, fn {_option, count} ->
        assert count >= 3 and count <= 7  # Allow some variance
      end)
    end
    
    test "projection consistency across read models" do
      poll_id = "consistency-poll-#{System.unique_integer([:positive])}"
      
      # Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Consistency Test Poll",
        description: "Testing projection consistency",
        options: ["Red", "Blue", "Green"],
        created_by: "test-creator",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      :timer.sleep(100)
      
      # Cast a series of votes with delays to test projection ordering
      vote_sequences = [
        {"alice", "option_1"},
        {"bob", "option_2"},
        {"charlie", "option_1"},
        {"diana", "option_3"},
        {"eve", "option_2"},
        {"frank", "option_1"}
      ]
      
      Enum.with_index(vote_sequences, fn {voter, option}, index ->
        command = %CastVoteCommand{
          poll_id: poll_id,
          option_id: option,
          voter_id: voter,
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(command)
        
        # Small delay between votes to test ordering
        if rem(index, 2) == 0, do: :timer.sleep(10)
      end)
      
      # Wait for all projections to complete
      :timer.sleep(300)
      
      # Verify consistency between read models
      {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
      {:ok, results} = Cachex.get(:poll_results, poll_id)
      
      # Both should show same total votes
      assert summary.total_votes == 6
      assert results.total_votes == 6
      
      # Verify individual votes match aggregated counts
      expected_counts = %{
        "option_1" => 3,  # alice, charlie, frank
        "option_2" => 2,  # bob, eve
        "option_3" => 1   # diana
      }
      
      assert summary.vote_counts == expected_counts
      
      # Verify individual votes in results
      assert results.votes["alice"] == "option_1"
      assert results.votes["bob"] == "option_2"
      assert results.votes["charlie"] == "option_1"
      assert results.votes["diana"] == "option_3"
      assert results.votes["eve"] == "option_2"
      assert results.votes["frank"] == "option_1"
      
      # Verify counts derived from individual votes match summary
      derived_counts = 
        results.votes
        |> Map.values()
        |> Enum.frequencies()
        
      assert derived_counts == expected_counts
    end
    
    test "error handling and recovery scenarios" do
      poll_id = "error-test-poll-#{System.unique_integer([:positive])}"
      
      # Test voting on non-existent poll
      vote_invalid_poll = %CastVoteCommand{
        poll_id: "non-existent-poll",
        option_id: "option_1",
        voter_id: "alice",
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, _reason} = CommandedApp.dispatch(vote_invalid_poll)
      
      # Initialize valid poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Error Test Poll",
        description: "Testing error scenarios",
        options: ["Valid Option"],
        created_by: "test-creator",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      :timer.sleep(100)
      
      # Test voting with invalid option
      vote_invalid_option = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "non_existent_option",
        voter_id: "alice",
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, :invalid_option} = CommandedApp.dispatch(vote_invalid_option)
      
      # Test valid vote after errors
      valid_vote = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_1",
        voter_id: "alice",
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(valid_vote)
      
      # Verify state is still consistent
      :timer.sleep(100)
      {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
      assert summary.total_votes == 1
    end
  end
  
  # Helper function to cleanup cache state
  defp cleanup_cache do
    # Clear all cache data between tests
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
