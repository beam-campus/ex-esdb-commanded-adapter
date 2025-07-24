defmodule SampleApp.Domain.InitializePoll.InitializePollTest do
  use ExUnit.Case, async: true
  
  alias SampleApp.Shared.Poll
  alias SampleApp.Domain.InitializePoll.{CommandV1, EventV1, MaybeInitializePollV1, InitializedToStateV1}
  
  describe "CommandV1 validation" do
    test "valid command passes validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Favorite Color?",
        description: "Choose your favorite color",
        options: ["Red", "Blue", "Green"],
        created_by: "user-456",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == :ok
    end
    
    test "command without poll_id fails validation" do
      command = %CommandV1{
        poll_id: nil,
        title: "Test Poll",
        options: ["A", "B"],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :poll_id_required}
    end
    
    test "command without title fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        title: nil,
        options: ["A", "B"],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :title_required}
    end
    
    test "command with less than 2 options fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Test Poll",
        options: ["Only One"],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :minimum_two_options}
    end
    
    test "command with empty options fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Test Poll", 
        options: ["Valid Option", ""],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :empty_options_not_allowed}
    end
    
    test "command with past expiration date fails validation" do
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Test Poll",
        options: ["A", "B"],
        created_by: "user-456",
        expires_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        requested_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :expiration_must_be_future}
    end
  end
  
  describe "EventV1 creation" do
    test "creates event from command with proper option IDs" do
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Favorite Color?",
        description: "Choose your favorite color",
        options: ["Red", "Blue", "Green"],
        created_by: "user-456",
        expires_at: nil,
        requested_at: DateTime.utc_now()
      }
      
      event = EventV1.from_command(command)
      
      assert event.poll_id == "poll-123"
      assert event.title == "Favorite Color?"
      assert event.description == "Choose your favorite color"
      assert event.created_by == "user-456"
      assert event.expires_at == nil
      assert event.version == 1
      
      # Check that options have proper IDs
      assert length(event.options) == 3
      assert Enum.at(event.options, 0) == %{id: "option_1", text: "Red"}
      assert Enum.at(event.options, 1) == %{id: "option_2", text: "Blue"}
      assert Enum.at(event.options, 2) == %{id: "option_3", text: "Green"}
    end
  end
  
  describe "MaybeInitializePollV1 command handling" do
    test "successfully initializes poll with valid command" do
      poll = Poll.new()
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Test Poll",
        options: ["Option A", "Option B"],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      result = MaybeInitializePollV1.execute(poll, command)
      
      assert %EventV1{} = result
      assert result.poll_id == "poll-123"
      assert result.title == "Test Poll"
    end
    
    test "fails to initialize already initialized poll" do
      poll = %Poll{poll_id: "existing-poll"}
      command = %CommandV1{
        poll_id: "poll-123",
        title: "Test Poll", 
        options: ["Option A", "Option B"],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      result = MaybeInitializePollV1.execute(poll, command)
      
      assert result == {:error, :poll_already_initialized}
    end
    
    test "fails with invalid command" do
      poll = Poll.new()
      command = %CommandV1{
        poll_id: "poll-123",
        title: nil,  # Invalid - no title
        options: ["Option A", "Option B"],
        created_by: "user-456",
        requested_at: DateTime.utc_now()
      }
      
      result = MaybeInitializePollV1.execute(poll, command)
      
      assert result == {:error, :title_required}
    end
  end
  
  describe "InitializedToStateV1 event application" do
    test "applies event to empty poll aggregate" do
      poll = Poll.new()
      event = %EventV1{
        poll_id: "poll-123",
        title: "Test Poll",
        description: "A test poll",
        options: [%{id: "option_1", text: "A"}, %{id: "option_2", text: "B"}],
        created_by: "user-456",
        expires_at: nil,
        initialized_at: DateTime.utc_now(),
        version: 1
      }
      
      updated_poll = InitializedToStateV1.apply(poll, event)
      
      assert updated_poll.poll_id == "poll-123"
      assert updated_poll.title == "Test Poll"
      assert updated_poll.description == "A test poll"
      assert updated_poll.options == event.options
      assert updated_poll.created_by == "user-456"
      assert updated_poll.status == :active
      assert updated_poll.votes == %{}
      assert updated_poll.closed_at == nil
    end
  end
end
