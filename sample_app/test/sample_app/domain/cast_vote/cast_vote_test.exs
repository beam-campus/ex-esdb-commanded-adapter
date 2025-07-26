defmodule SampleApp.Domain.CastVote.CastVoteTest do
  use ExUnit.Case, async: true
  
  alias SampleApp.Aggregates.Poll
  alias SampleApp.Domain.CastVote.{CommandV1, EventV1, MaybeCastVoteV1, CastedToStateV1}
  
  describe "CommandV1 validation" do
    test "valid command passes validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        option_id: "option-1",
        voter_id: "voter-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == :ok
    end
    
    test "command without poll_id fails validation" do
      command = %CommandV1{
        poll_id: nil,
        option_id: "option-1",
        voter_id: "voter-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :poll_id_required}
    end
    
    test "command without option_id fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        option_id: nil,
        voter_id: "voter-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :option_id_required}
    end
    
    test "command without voter_id fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        option_id: "option-1",
        voter_id: nil,
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :voter_id_required}
    end
  end
  
  describe "EventV1 creation" do
    test "creates event from command" do
      command = %CommandV1{
        poll_id: "poll-123",
        option_id: "option-1",
        voter_id: "voter-456",
        requested_at: DateTime.utc_now()
      }
      
      event = EventV1.from_command(command)
      
      assert event.poll_id == "poll-123"
      assert event.option_id == "option-1"
      assert event.voter_id == "voter-456"
      assert event.version == 1
    end
  end
  
  describe "MaybeCastVoteV1 command handling" do
    setup do
      poll = %Poll{
        poll_id: "poll-123",
        status: :active,
        options: [%{id: "option-1", text: "Option 1"}, %{id: "option-2", text: "Option 2"}],
        votes: %{
          "voter-123" => "option-1"
        }
      }

      command = %CommandV1{
        poll_id: "poll-123",
        option_id: "option-2",
        voter_id: "voter-456",
        requested_at: DateTime.utc_now()
      }

      {:ok, poll: poll, command: command}
    end

    test "successfully casts vote with valid command", %{poll: poll, command: command} do
      result = MaybeCastVoteV1.execute(poll, command)
      assert %EventV1{} = result
      assert result.poll_id == "poll-123"
      assert result.option_id == "option-2"
    end
    
    test "fails if poll does not exist", %{command: command} do
      poll = %Poll{poll_id: nil}

      result = MaybeCastVoteV1.execute(poll, command)
      
      assert result == {:error, :poll_not_found}
    end
    
    test "fails if poll is closed", %{poll: poll, command: command} do
      closed_poll = %Poll{poll | status: :closed}

      result = MaybeCastVoteV1.execute(closed_poll, command)
      
      assert result == {:error, :poll_closed}
    end

    test "fails if option does not exist", %{poll: poll, command: command} do
      invalid_command = %CommandV1{
        command | option_id: "invalid-option"
      }

      result = MaybeCastVoteV1.execute(poll, invalid_command)

      assert result == {:error, :invalid_option}
    end

    test "fails if voter has already voted", %{poll: poll} do
      command_with_existing_voter = %CommandV1{
        poll_id: "poll-123",
        option_id: "option-1",
        voter_id: "voter-123",
        requested_at: DateTime.utc_now()
      }

      result = MaybeCastVoteV1.execute(poll, command_with_existing_voter)

      assert result == {:error, :voter_already_voted}
    end
  end

  describe "CastedToStateV1 event application" do
    test "applies vote to poll aggregate" do
      poll = %Poll{votes: %{}, poll_id: "poll-123"}
      event = %EventV1{
        poll_id: "poll-123",
        option_id: "option-1",
        voter_id: "voter-456",
        voted_at: DateTime.utc_now(),
        version: 1
      }

      updated_poll = CastedToStateV1.apply(poll, event)

      assert updated_poll.votes["voter-456"] == "option-1"
    end
  end
end

