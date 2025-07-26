defmodule SampleApp.Property.VotingPropertiesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  
  alias SampleApp.CommandedApp
  alias SampleApp.Domain.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.Domain.CastVote.CommandV1, as: CastVoteCommand
  
  @moduletag :property
  
  describe "Voting system properties" do
    setup do
      # Clean state for each property test
      cleanup_cache()
      
      on_exit(fn ->
        cleanup_cache()
      end)
      
      :ok
    end
    
    property "total votes never exceeds number of unique voters" do
      check all poll_data <- poll_with_votes_generator(),
                max_runs: 50 do
        
        {poll_id, votes} = poll_data
        
        # Initialize poll
        init_command = %InitializePollCommand{
          poll_id: poll_id,
          title: "Property Test Poll",
          description: "Testing vote counting properties",
          options: ["Option 1", "Option 2", "Option 3"],
          created_by: "test-creator",
          expires_at: nil,
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(init_command)
        :timer.sleep(50)
        
        # Cast all votes
        Enum.each(votes, fn {voter_id, option_id} ->
          vote_command = %CastVoteCommand{
            poll_id: poll_id,
            option_id: option_id,
            voter_id: voter_id,
            requested_at: DateTime.utc_now()
          }
          
          # We don't assert success here because duplicate votes should fail
          CommandedApp.dispatch(vote_command)
        end)
        
        # Wait for projections
        :timer.sleep(100)
        
        # Check invariant: total votes <= unique voters
        {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
        {:ok, results} = Cachex.get(:poll_results, poll_id)
        
        unique_voters = votes |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()
        
        assert summary.total_votes <= unique_voters
        assert results.total_votes <= unique_voters
        assert summary.total_votes == results.total_votes
        
        # The actual total should equal unique voters (since duplicates are rejected)
        assert summary.total_votes == unique_voters
      end
    end
    
    property "vote counts are consistent across read models" do
      check all poll_data <- poll_with_votes_generator(),
                max_runs: 30 do
        
        {poll_id, votes} = poll_data
        
        # Initialize poll
        init_command = %InitializePollCommand{
          poll_id: poll_id,
          title: "Consistency Test Poll",
          description: "Testing consistency properties",
          options: ["A", "B", "C", "D"],
          created_by: "test-creator",
          expires_at: nil,
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(init_command)
        :timer.sleep(50)
        
        # Cast unique votes only (filter duplicates)
        unique_votes = Enum.uniq_by(votes, &elem(&1, 0))
        
        Enum.each(unique_votes, fn {voter_id, option_id} ->
          vote_command = %CastVoteCommand{
            poll_id: poll_id,
            option_id: option_id,
            voter_id: voter_id,
            requested_at: DateTime.utc_now()
          }
          
          assert :ok = CommandedApp.dispatch(vote_command)
        end)
        
        :timer.sleep(150)
        
        # Check consistency between read models
        {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
        {:ok, results} = Cachex.get(:poll_results, poll_id)
        
        # Both should have same total
        assert summary.total_votes == results.total_votes
        
        # Derive counts from individual votes
        derived_counts = 
          results.votes
          |> Map.values()
          |> Enum.frequencies()
        
        # Remove zero counts from summary for comparison
        summary_counts = 
          summary.vote_counts
          |> Enum.filter(fn {_option, count} -> count > 0 end)
          |> Map.new()
        
        # Counts should match
        assert derived_counts == summary_counts
        
        # Total should equal sum of all option counts
        count_sum = summary.vote_counts |> Map.values() |> Enum.sum()
        assert summary.total_votes == count_sum
      end
    end
    
    property "poll state transitions are monotonic" do
      check all poll_id <- poll_id_generator(),
                max_runs: 20 do
        
        # Initialize poll (should always succeed for unique IDs)
        init_command = %InitializePollCommand{
          poll_id: poll_id,
          title: "State Transition Test",
          description: "Testing state monotonicity",
          options: ["Option 1", "Option 2"],
          created_by: "test-creator",
          expires_at: nil,
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(init_command)
        :timer.sleep(50)
        
        # Poll should start active
        {:ok, initial_summary} = Cachex.get(:poll_summaries, poll_id)
        assert initial_summary.status == :active
        assert initial_summary.total_votes == 0
        
        # Cast some votes
        vote1_command = %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_1",
          voter_id: "voter1",
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(vote1_command)
        :timer.sleep(50)
        
        # Vote count should increase monotonically
        {:ok, after_vote_summary} = Cachex.get(:poll_summaries, poll_id)
        assert after_vote_summary.total_votes >= initial_summary.total_votes
        assert after_vote_summary.status == :active  # Still active
        
        # Add another vote
        vote2_command = %CastVoteCommand{
          poll_id: poll_id,
          option_id: "option_2",
          voter_id: "voter2",
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(vote2_command)
        :timer.sleep(50)
        
        # Vote count should continue to increase
        {:ok, final_summary} = Cachex.get(:poll_summaries, poll_id)
        assert final_summary.total_votes >= after_vote_summary.total_votes
        assert final_summary.total_votes == 2
      end
    end
    
    property "option IDs are preserved correctly" do
      check all {poll_id, options_data} <- poll_with_options_generator(),
                max_runs: 20 do
        
        {option_texts, votes} = options_data
        
        # Initialize poll with generated options
        init_command = %InitializePollCommand{
          poll_id: poll_id,
          title: "Option ID Test Poll",
          description: "Testing option ID preservation",
          options: option_texts,
          created_by: "test-creator",
          expires_at: nil,
          requested_at: DateTime.utc_now()
        }
        
        assert :ok = CommandedApp.dispatch(init_command)
        :timer.sleep(50)
        
        # Cast votes using generated option IDs
        Enum.each(votes, fn {voter_id, option_id} ->
          vote_command = %CastVoteCommand{
            poll_id: poll_id,
            option_id: option_id,
            voter_id: voter_id,
            requested_at: DateTime.utc_now()
          }
          
          # Should succeed for valid option IDs
          result = CommandedApp.dispatch(vote_command)
          valid_option_ids = Enum.with_index(option_texts, 1) |> Enum.map(fn {_, i} -> "option_#{i}" end)
          
          if option_id in valid_option_ids do
            assert :ok = result
          else
            assert {:error, :invalid_option} = result
          end
        end)
        
        :timer.sleep(100)
        
        # Verify only valid votes were counted
        {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
        {:ok, results} = Cachex.get(:poll_results, poll_id)
        
        # Check that all recorded votes have valid option IDs
        valid_option_ids = Enum.with_index(option_texts, 1) |> Enum.map(fn {_, i} -> "option_#{i}" end)
        
        Enum.each(results.votes, fn {_voter, option_id} ->
          assert option_id in valid_option_ids
        end)
        
        Enum.each(summary.vote_counts, fn {option_id, count} ->
          if count > 0 do
            assert option_id in valid_option_ids
          end
        end)
      end
    end
  end
  
  # Generators for property-based testing
  
  defp poll_id_generator do
    gen all id_suffix <- StreamData.positive_integer() do
      "prop-test-poll-#{id_suffix}"
    end
  end
  
  defp poll_with_votes_generator do
    gen all poll_id <- poll_id_generator(),
            votes <- votes_generator() do
      {poll_id, votes}
    end
  end
  
  defp votes_generator do
    gen all voter_count <- StreamData.integer(1..20),
            voters <- StreamData.list_of(voter_id_generator(), length: voter_count),
            options <- StreamData.list_of(option_id_generator(), length: voter_count) do
      Enum.zip(voters, options)
    end
  end
  
  defp voter_id_generator do
    gen all suffix <- StreamData.positive_integer() do
      "voter_#{suffix}"
    end
  end
  
  defp option_id_generator do
    StreamData.member_of(["option_1", "option_2", "option_3", "option_4"])
  end
  
  defp poll_with_options_generator do
    gen all poll_id <- poll_id_generator(),
            option_count <- StreamData.integer(2..8),
            option_texts <- StreamData.list_of(StreamData.string(:alphanumeric, min_length: 1, max_length: 20), length: option_count),
            vote_count <- StreamData.integer(0..15),
            votes <- StreamData.list_of(
              StreamData.tuple([
                voter_id_generator(),
                # Mix of valid and invalid option IDs to test error handling
                StreamData.frequency([
                  {8, StreamData.member_of(Enum.with_index(option_texts, 1) |> Enum.map(fn {_, i} -> "option_#{i}" end))},
                  {2, StreamData.constant("invalid_option_id")}
                ])
              ]),
              length: vote_count
            ) do
      {poll_id, {option_texts, votes}}
    end
  end
  
  # Helper functions
  
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
