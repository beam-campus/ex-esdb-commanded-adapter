defmodule SampleApp.Domain.ClosePoll.ClosePollTest do
  use ExUnit.Case, async: true
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.ClosePoll.{CommandV1, EventV1, MaybeClosePollV1, ClosedToStateV1}
  
  describe "CommandV1 validation" do
    test "valid command passes validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        closed_by: "user-456",
        reason: "Testing closure",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == :ok
    end
    
    test "command without poll_id fails validation" do
      command = %CommandV1{
        poll_id: nil,
        closed_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :poll_id_required}
    end
    
    test "command without closed_by fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        closed_by: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :closed_by_required}
    end
  end
  
  describe "EventV1 creation" do
    test "creates event from command" do
      command = %CommandV1{
        poll_id: "poll-123",
        closed_by: "user-456",
        reason: "Testing",
        requested_at: DateTime.utc_now()
      }
      
      event = EventV1.from_command(command)
      
      assert event.poll_id == "poll-123"
      assert event.closed_by == "user-456"
      assert event.reason == "Testing"
      assert event.version == 1
    end
  end
  
  describe "MaybeClosePollV1 command handling" do
    setup do
      poll = %Poll{
        poll_id: "poll-123",
        status: :active,
        created_by: "user-456",
        options: [%{id: "option-1", text: "Option 1"}],
        votes: %{}
      }

      command = %CommandV1{
        poll_id: "poll-123",
        closed_by: "user-456",
        reason: "Testing closure",
        requested_at: DateTime.utc_now()
      }

      {:ok, poll: poll, command: command}
    end

    test "successfully closes poll with valid command", %{poll: poll, command: command} do
      result = MaybeClosePollV1.execute(poll, command)
      
      assert %EventV1{} = result
      assert result.poll_id == "poll-123"
      assert result.closed_by == "user-456"
      assert result.reason == "Testing closure"
    end
    
    test "fails if poll does not exist", %{command: command} do
      poll = %Poll{poll_id: nil}

      result = MaybeClosePollV1.execute(poll, command)
      
      assert result == {:error, :poll_not_found}
    end
    
    test "fails if poll is already closed", %{poll: poll, command: command} do
      closed_poll = %Poll{poll | status: :closed}

      result = MaybeClosePollV1.execute(closed_poll, command)
      
      assert result == {:error, :poll_already_closed}
    end
    
    test "fails if poll is expired", %{poll: poll, command: command} do
      expired_poll = %Poll{poll | status: :expired}

      result = MaybeClosePollV1.execute(expired_poll, command)
      
      assert result == {:error, :poll_expired}
    end

    test "fails if user is not poll creator", %{poll: poll, command: command} do
      different_user_command = %CommandV1{
        command | closed_by: "different-user"
      }

      result = MaybeClosePollV1.execute(poll, different_user_command)

      assert result == {:error, :not_poll_creator}
    end
  end

  describe "ClosedToStateV1 event application" do
    test "applies closure to poll aggregate" do
      poll = %Poll{
        poll_id: "poll-123", 
        status: :active,
        closed_at: nil
      }
      
      event = %EventV1{
        poll_id: "poll-123",
        closed_by: "user-456",
        reason: "Testing",
        closed_at: DateTime.utc_now(),
        version: 1
      }

      updated_poll = ClosedToStateV1.apply(poll, event)

      assert updated_poll.status == :closed
      assert updated_poll.closed_at == event.closed_at
    end
  end
end
