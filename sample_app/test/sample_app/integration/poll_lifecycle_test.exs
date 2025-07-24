defmodule SampleApp.Integration.PollLifecycleTest do
  use ExUnit.Case, async: false
  
  alias SampleApp.CommandedApp
  alias SampleApp.Domain.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.Domain.CastVote.CommandV1, as: CastVoteCommand
  alias SampleApp.Domain.ClosePoll.CommandV1, as: ClosePollCommand
  alias SampleApp.Domain.ExpireCountdown.CommandV1, as: ExpireCountdownCommand
  alias SampleApp.Domain.StartExpirationCountdown.CommandV1, as: StartExpirationCountdownCommand

  @moduletag :integration
  
  describe "Complete poll lifecycle integration" do
    test "can create poll, cast votes, and close poll" do
      poll_id = "integration-poll-#{System.unique_integer()}"
      requested_at = DateTime.utc_now()
      
      # Initialize poll
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Integration Test Poll",
        description: "Testing complete poll lifecycle",
        options: ["Option 1", "Option 2"],
        created_by: "test-creator",
        requested_at: requested_at,
        expires_at: nil  # No expiration for this test
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      
      # Cast some votes
      vote1_command = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_1",
        voter_id: "voter1",
        requested_at: DateTime.utc_now()
      }
      
      vote2_command = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_2", 
        voter_id: "voter2",
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(vote1_command)
      assert :ok = CommandedApp.dispatch(vote2_command)
      
      # Close poll
      close_command = %ClosePollCommand{
        poll_id: poll_id,
        closed_by: "test-creator",
        reason: "Integration test complete",
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(close_command)
    end

    test "can create poll with expiration and start countdown" do
      poll_id = "expiration-poll-#{System.unique_integer()}"
      created_at = DateTime.utc_now()
      expires_at = DateTime.add(created_at, 3600) # 1 hour from now
      
      # Initialize poll with expiration
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Poll with Expiration",
        description: "Testing expiration countdown",
        options: ["Yes", "No"],
        created_by: "test-creator",
        requested_at: created_at,
        expires_at: expires_at
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      
      # The policy should automatically start the expiration countdown
      # In a real system, we'd have a way to observe this event
      # For now, we can manually trigger the countdown start
      
      start_countdown_command = %StartExpirationCountdownCommand{
        poll_id: poll_id,
        expires_at: expires_at,
        started_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(start_countdown_command)
      
      # Simulate expiration (normally handled by external scheduler)
      expire_command = %ExpireCountdownCommand{
        poll_id: poll_id,
        expired_at: expires_at
      }
      
      assert :ok = CommandedApp.dispatch(expire_command)
    end
    
    test "validates business rules across command boundaries" do
      poll_id = "validation-poll-#{System.unique_integer()}"
      
      # Try to vote on non-existent poll
      vote_command = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option1",
        voter_id: "voter1",
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, :poll_not_found} = CommandedApp.dispatch(vote_command)
      
      # Initialize poll first
      init_command = %InitializePollCommand{
        poll_id: poll_id,
        title: "Validation Test Poll", 
        description: "Testing business rule validation",
        options: ["Option 1", "Option 2"],
        created_by: "test-creator",
        requested_at: DateTime.utc_now(),
        expires_at: nil
      }
      
      assert :ok = CommandedApp.dispatch(init_command)
      
      # Try to vote on invalid option
      invalid_vote_command = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "invalid_option",
        voter_id: "voter1",
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, :invalid_option} = CommandedApp.dispatch(invalid_vote_command)
      
      # Cast valid vote
      valid_vote_command = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_1",
        voter_id: "voter1", 
        requested_at: DateTime.utc_now()
      }
      
      assert :ok = CommandedApp.dispatch(valid_vote_command)
      
      # Try to vote again with same voter
      duplicate_vote_command = %CastVoteCommand{
        poll_id: poll_id,
        option_id: "option_1",
        voter_id: "voter1",
        requested_at: DateTime.utc_now()
      }
      
      assert {:error, :voter_already_voted} = CommandedApp.dispatch(duplicate_vote_command)
    end
  end
end
