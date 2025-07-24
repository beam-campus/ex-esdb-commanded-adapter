defmodule SampleApp.Domain.ExpireCountdownTest do
  use ExUnit.Case, async: true
  
  alias SampleApp.Domain.ExpireCountdown.{CommandV1, EventV1, MaybeExpireCountdownV1, EventHandlerV1}
  alias SampleApp.Shared.Poll
  
  describe "ExpireCountdown.CommandV1" do
    test "creates valid command with required fields" do
      expired_at = DateTime.utc_now()
      
      command = %CommandV1{
        poll_id: "poll-123",
        expired_at: expired_at
      }
      
      assert command.poll_id == "poll-123"
      assert command.expired_at == expired_at
    end
    
    test "validates poll_id is present" do
      assert_raise ArgumentError, "poll_id is required", fn ->
        CommandV1.validate!(%CommandV1{poll_id: nil, expired_at: DateTime.utc_now()})
      end
    end
    
    test "validates expired_at is present" do
      assert_raise ArgumentError, "expired_at is required", fn ->
        CommandV1.validate!(%CommandV1{poll_id: "poll-123", expired_at: nil})
      end
    end
    
    test "validates expired_at is a DateTime" do
      assert_raise ArgumentError, "expired_at must be a DateTime", fn ->
        CommandV1.validate!(%CommandV1{poll_id: "poll-123", expired_at: "not-a-datetime"})
      end
    end
  end
  
  describe "ExpireCountdown.EventV1" do
    test "creates event from valid command" do
      expired_at = DateTime.utc_now()
      command = %CommandV1{
        poll_id: "poll-123",
        expired_at: expired_at
      }
      
      event = EventV1.from_command(command)
      
      assert event.poll_id == "poll-123"
      assert event.expired_at == expired_at
      assert event.version == 1
    end
    
    test "returns correct event type" do
      assert EventV1.event_type() == "countdown_expired:v1"
    end
    
    test "can be JSON encoded" do
      expired_at = DateTime.utc_now()
      event = %EventV1{
        poll_id: "poll-123",
        expired_at: expired_at,
        version: 1
      }
      
      json = Jason.encode!(event)
      decoded = Jason.decode!(json)
      
      assert decoded["poll_id"] == "poll-123"
      assert decoded["version"] == 1
    end
  end
  
  describe "ExpireCountdown.MaybeExpireCountdownV1" do
    test "executes expire countdown command and creates event" do
      expired_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        expires_at: expired_at
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expired_at: expired_at
      }
      
      event = MaybeExpireCountdownV1.execute(poll, command)
      
      assert %EventV1{} = event
      assert event.poll_id == "poll-123"
      assert event.expired_at == expired_at
    end

    test "returns error if poll already expired" do
      expired_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        status: :expired,
        expires_at: expired_at
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expired_at: expired_at
      }

      assert {:error, :poll_already_expired} = MaybeExpireCountdownV1.execute(poll, command)
    end

    test "returns error if expiration time does not match" do
      expired_at = DateTime.utc_now()
      incorrect_expired_at = DateTime.add(expired_at, 3600)
      
      poll = %Poll{
        poll_id: "poll-123",
        expires_at: expired_at
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expired_at: incorrect_expired_at
      }

      assert {:error, :expiration_time_mismatch} = MaybeExpireCountdownV1.execute(poll, command)
    end
  end
  
  describe "ExpireCountdown.EventHandlerV1" do
    test "applies countdown expired event to poll" do
      expired_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        title: "Test Poll",
        status: :active,
        votes: %{}
      }
      
      event = %EventV1{
        poll_id: "poll-123",
        expired_at: expired_at,
        version: 1
      }
      
      updated_poll = EventHandlerV1.apply(poll, event)
      
      assert updated_poll.status == :expired
      assert updated_poll.expired_at == expired_at
      assert updated_poll.poll_id == "poll-123"
      assert updated_poll.title == "Test Poll"
    end
    
    test "preserves other poll fields when applying event" do
      expired_at = DateTime.utc_now()
      created_at = DateTime.add(expired_at, -3600)
      expires_at = DateTime.add(expired_at, -60)
      
      poll = %Poll{
        poll_id: "poll-123",
        title: "Test Poll",
        description: "A test poll",
        status: :active,
        votes: %{"user1" => "option1", "user2" => "option2"},
        options: [
          %{id: "option1", text: "Option 1"},
          %{id: "option2", text: "Option 2"}
        ],
        created_by: "creator-123",
        created_at: created_at,
        expires_at: expires_at
      }
      
      event = %EventV1{
        poll_id: "poll-123",
        expired_at: expired_at,
        version: 1
      }
      
      updated_poll = EventHandlerV1.apply(poll, event)
      
      # Status and expired_at should be updated
      assert updated_poll.status == :expired
      assert updated_poll.expired_at == expired_at
      
      # All other fields should be preserved
      assert updated_poll.poll_id == poll.poll_id
      assert updated_poll.title == poll.title
      assert updated_poll.description == poll.description
      assert updated_poll.votes == poll.votes
      assert updated_poll.options == poll.options
      assert updated_poll.created_by == poll.created_by
      assert updated_poll.created_at == poll.created_at
      assert updated_poll.expires_at == poll.expires_at
    end
  end
  
  describe "Poll aggregate integration" do
    test "poll can apply countdown expired event" do
      expired_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        title: "Test Poll",
        status: :active,
        votes: %{}
      }
      
      event = %EventV1{
        poll_id: "poll-123",
        expired_at: expired_at,
        version: 1
      }
      
      updated_poll = Poll.apply(poll, event)
      
      assert updated_poll.status == :expired
      assert updated_poll.expired_at == expired_at
    end
    
    test "expired poll is considered closed" do
      expired_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        title: "Test Poll",
        status: :expired,
        expired_at: expired_at,
        votes: %{}
      }
      
      assert Poll.closed?(poll) == true
      assert Poll.active?(poll) == false
    end
  end
end
