defmodule SampleApp.Domain.CastVote.CastedToStateV1Test do
  use ExUnit.Case, async: true
  
  alias SampleApp.Domain.CastVote.{EventV1, CastedToStateV1}
  alias SampleApp.Aggregates.Poll
  
  describe "CastedToStateV1 aggregate state update" do
    setup do
      # Create a test event
      event = %EventV1{
        poll_id: "test-poll-123",
        option_id: "option_1",
        voter_id: "voter-456",
        voted_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Create initial poll state
      initial_poll = %Poll{
        poll_id: "test-poll-123",
        title: "Test Poll",
        description: "A test poll",
        options: [
          %{id: "option_1", text: "Option 1"},
          %{id: "option_2", text: "Option 2"}
        ],
        created_by: "test-creator",
        status: :active,
        votes: %{},  # No votes initially
        expires_at: nil,
        created_at: ~U[2024-01-01 09:00:00Z],
        closed_at: nil
      }
      
      {:ok, event: event, initial_poll: initial_poll}
    end
    
    test "✅ SELF-CONTAINED: only uses event data and current aggregate state", %{event: event, initial_poll: initial_poll} do
      # Apply the event to the aggregate
      updated_poll = CastedToStateV1.apply(initial_poll, event)
      
      # Verify the vote was added correctly
      assert updated_poll.votes["voter-456"] == "option_1"
      assert updated_poll.poll_id == "test-poll-123"
      assert updated_poll.title == "Test Poll"
      assert updated_poll.status == :active
      
      # Other fields should remain unchanged
      assert updated_poll.options == initial_poll.options
      assert updated_poll.created_by == initial_poll.created_by
      assert updated_poll.created_at == initial_poll.created_at
    end
    
    test "✅ EVENT TIMESTAMPS: uses event data correctly", %{initial_poll: initial_poll} do
      # Create event with specific data
      specific_time = ~U[2024-06-15 14:30:00Z]
      event = %EventV1{
        poll_id: "test-poll-456",
        option_id: "option_2",
        voter_id: "voter-789",
        voted_at: specific_time,
        version: 1
      }
      
      # Apply the event
      updated_poll = CastedToStateV1.apply(initial_poll, event)
      
      # Verify the correct vote was recorded
      assert updated_poll.votes["voter-789"] == "option_2"
      
      # The aggregate doesn't store vote timestamps, but uses event data correctly
      assert map_size(updated_poll.votes) == 1
    end
    
    test "handles multiple votes from different voters", %{initial_poll: initial_poll} do
      # Create multiple events
      event1 = %EventV1{
        poll_id: "test-poll-123",
        option_id: "option_1",
        voter_id: "voter-1",
        voted_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      event2 = %EventV1{
        poll_id: "test-poll-123",
        option_id: "option_2",
        voter_id: "voter-2",
        voted_at: ~U[2024-01-01 10:01:00Z],
        version: 1
      }
      
      event3 = %EventV1{
        poll_id: "test-poll-123",
        option_id: "option_1",
        voter_id: "voter-3",
        voted_at: ~U[2024-01-01 10:02:00Z],
        version: 1
      }
      
      # Apply events sequentially
      poll_after_event1 = CastedToStateV1.apply(initial_poll, event1)
      poll_after_event2 = CastedToStateV1.apply(poll_after_event1, event2)
      final_poll = CastedToStateV1.apply(poll_after_event2, event3)
      
      # Verify all votes were recorded
      assert final_poll.votes["voter-1"] == "option_1"
      assert final_poll.votes["voter-2"] == "option_2"
      assert final_poll.votes["voter-3"] == "option_1"
      assert map_size(final_poll.votes) == 3
    end
    
    test "overwrites previous vote from same voter", %{initial_poll: initial_poll} do
      # Add initial vote
      poll_with_vote = %{initial_poll | votes: %{"voter-123" => "option_1"}}
      
      # Create event for same voter with different option
      event = %EventV1{
        poll_id: "test-poll-123",
        option_id: "option_2",
        voter_id: "voter-123",
        voted_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Apply the event
      updated_poll = CastedToStateV1.apply(poll_with_vote, event)
      
      # Verify the vote was updated
      assert updated_poll.votes["voter-123"] == "option_2"
      assert map_size(updated_poll.votes) == 1
    end
    
    test "maintains aggregate immutability", %{event: event, initial_poll: initial_poll} do
      # Apply the event
      updated_poll = CastedToStateV1.apply(initial_poll, event)
      
      # Verify original poll was not modified
      assert initial_poll.votes == %{}
      assert updated_poll.votes == %{"voter-456" => "option_1"}
      
      # Verify they are different instances
      refute initial_poll == updated_poll
    end
    
    test "handles empty votes map correctly", %{event: event} do
      # Create poll with no existing votes
      poll_with_no_votes = %Poll{
        poll_id: "empty-poll",
        votes: %{}
      }
      
      # Apply the event
      updated_poll = CastedToStateV1.apply(poll_with_no_votes, event)
      
      # Verify vote was added
      assert updated_poll.votes == %{"voter-456" => "option_1"}
    end
    
    test "preserves all other aggregate fields", %{event: event, initial_poll: initial_poll} do
      # Apply the event
      updated_poll = CastedToStateV1.apply(initial_poll, event)
      
      # Verify all other fields are preserved
      assert updated_poll.poll_id == initial_poll.poll_id
      assert updated_poll.title == initial_poll.title
      assert updated_poll.description == initial_poll.description
      assert updated_poll.options == initial_poll.options
      assert updated_poll.created_by == initial_poll.created_by
      assert updated_poll.status == initial_poll.status
      assert updated_poll.expires_at == initial_poll.expires_at
      assert updated_poll.created_at == initial_poll.created_at
      assert updated_poll.closed_at == initial_poll.closed_at
      
      # Only votes should be different
      refute updated_poll.votes == initial_poll.votes
    end
  end
end
