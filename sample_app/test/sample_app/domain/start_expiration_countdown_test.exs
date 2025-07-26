defmodule SampleApp.Domain.StartExpirationCountdownTest do
  use ExUnit.Case, async: true
  
  alias SampleApp.Domain.StartExpirationCountdown.{CommandV1, EventV1, MaybeStartExpirationCountdownV1, CountdownStartedToStateV1}
  alias SampleApp.Aggregates.Poll
  
  describe "StartExpirationCountdown.CommandV1" do
    test "creates valid command with required fields" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }
      
      assert command.poll_id == "poll-123"
      assert command.expires_at == expires_at
      assert command.started_at == started_at
    end
    
    test "validates poll_id is present" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      
      assert_raise ArgumentError, "poll_id is required", fn ->
        CommandV1.validate!(%CommandV1{poll_id: nil, expires_at: expires_at, started_at: DateTime.utc_now()})
      end
    end
    
    test "validates expires_at is present" do
      assert_raise ArgumentError, "expires_at is required", fn ->
        CommandV1.validate!(%CommandV1{poll_id: "poll-123", expires_at: nil, started_at: DateTime.utc_now()})
      end
    end
    
    test "validates expires_at is in the future" do
      past_time = DateTime.add(DateTime.utc_now(), -3600)
      
      assert_raise ArgumentError, "expiration must be in the future", fn ->
        CommandV1.validate!(%CommandV1{poll_id: "poll-123", expires_at: past_time, started_at: DateTime.utc_now()})
      end
    end
    
    test "valid? returns :ok for valid command" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == :ok
    end
    
    test "valid? returns error for invalid poll_id" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      command = %CommandV1{
        poll_id: nil,
        expires_at: expires_at,
        started_at: DateTime.utc_now()
      }
      
      assert CommandV1.valid?(command) == {:error, :poll_id_required}
    end
  end
  
  describe "StartExpirationCountdown.EventV1" do
    test "creates event from valid command" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }
      
      event = EventV1.from_command(command)
      
      assert event.poll_id == "poll-123"
      assert event.expires_at == expires_at
      assert event.started_at == started_at
      assert event.version == 1
    end
    
    test "returns correct event type" do
      assert EventV1.event_type() == "expiration_countdown_started:v1"
    end
    
    test "can be JSON encoded" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      event = %EventV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at,
        version: 1
      }
      
      json = Jason.encode!(event)
      decoded = Jason.decode!(json)
      
      assert decoded["poll_id"] == "poll-123"
      assert decoded["version"] == 1
    end
  end
  
  describe "StartExpirationCountdown.MaybeStartExpirationCountdownV1" do
    test "executes start expiration countdown command and creates event" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        status: :active,
        expires_at: expires_at
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }
      
      event = MaybeStartExpirationCountdownV1.execute(poll, command)
      
      assert %EventV1{} = event
      assert event.poll_id == "poll-123"
      assert event.expires_at == expires_at
      assert event.started_at == started_at
    end

    test "returns error if poll not found" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      poll = %Poll{poll_id: nil}

      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }

      assert {:error, :poll_not_found} = MaybeStartExpirationCountdownV1.execute(poll, command)
    end

    test "returns error if poll is not active" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        status: :closed,
        expires_at: expires_at
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }

      assert {:error, :poll_closed} = MaybeStartExpirationCountdownV1.execute(poll, command)
    end
    
    test "returns error if poll is expired" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        status: :expired,
        expires_at: expires_at
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }

      assert {:error, :poll_expired} = MaybeStartExpirationCountdownV1.execute(poll, command)
    end
    
    test "returns error if poll has no expiration" do
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        status: :active,
        expires_at: nil
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: DateTime.add(DateTime.utc_now(), 3600),
        started_at: started_at
      }

      assert {:error, :poll_has_no_expiration} = MaybeStartExpirationCountdownV1.execute(poll, command)
    end

    test "returns error for invalid command" do
      expires_at = DateTime.add(DateTime.utc_now(), -3600) # Past time
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        status: :active,
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      }

      command = %CommandV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at
      }

      assert {:error, :expiration_must_be_future} = MaybeStartExpirationCountdownV1.execute(poll, command)
    end
  end
  
  describe "StartExpirationCountdown.CountdownStartedToStateV1" do
    test "applies expiration countdown started event to poll" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        title: "Test Poll",
        status: :active,
        votes: %{}
      }
      
      event = %EventV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at,
        version: 1
      }
      
      updated_poll = CountdownStartedToStateV1.apply(poll, event)
      
      # Currently the event handler is a no-op, so poll should be unchanged
      assert updated_poll == poll
      assert updated_poll.poll_id == "poll-123"
      assert updated_poll.title == "Test Poll"
      assert updated_poll.status == :active
    end
    
    test "preserves all poll fields when applying event" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      created_at = DateTime.add(DateTime.utc_now(), -1800)
      
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
        expires_at: expires_at,
        started_at: started_at,
        version: 1
      }
      
      updated_poll = CountdownStartedToStateV1.apply(poll, event)
      
      # All fields should be preserved since it's currently a no-op
      assert updated_poll.poll_id == poll.poll_id
      assert updated_poll.title == poll.title
      assert updated_poll.description == poll.description
      assert updated_poll.votes == poll.votes
      assert updated_poll.options == poll.options
      assert updated_poll.created_by == poll.created_by
      assert updated_poll.created_at == poll.created_at
      assert updated_poll.expires_at == poll.expires_at
      assert updated_poll.status == poll.status
    end
  end
  
  describe "Poll aggregate integration" do
    test "poll can apply expiration countdown started event" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600)
      started_at = DateTime.utc_now()
      
      poll = %Poll{
        poll_id: "poll-123",
        title: "Test Poll",
        status: :active,
        votes: %{}
      }
      
      event = %EventV1{
        poll_id: "poll-123",
        expires_at: expires_at,
        started_at: started_at,
        version: 1
      }
      
      updated_poll = Poll.apply(poll, event)
      
      # Since CountdownStartedToStateV1 is a no-op, poll should be unchanged
      assert updated_poll == poll
    end
  end
end
