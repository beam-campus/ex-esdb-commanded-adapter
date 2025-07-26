defmodule SampleApp.Domain.InitializePoll.InitializedToStateV1Test do
  use ExUnit.Case, async: true
  
  alias SampleApp.Domain.InitializePoll.{EventV1, InitializedToStateV1}
  alias SampleApp.Aggregates.Poll
  
  describe "InitializedToStateV1 aggregate state handler" do
    setup do
      # Create a test event
      event = %EventV1{
        poll_id: "test-poll-123",
        title: "Favorite Color?",
        description: "Choose your favorite color",
        options: [
          %{id: "option_1", text: "Red"},
          %{id: "option_2", text: "Blue"},
          %{id: "option_3", text: "Green"}
        ],
        created_by: "test-creator",
        expires_at: ~U[2024-01-02 10:00:00Z],
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Initial state (should be empty for initialization)
      initial_state = %Poll{}
      
      {:ok, event: event, initial_state: initial_state}
    end
    
    test "✅ IMMUTABLE: creates new state without mutating input", %{event: event, initial_state: initial_state} do
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify original state was not modified
      assert initial_state == %Poll{}
      
      # Verify new state is different and properly initialized
      assert new_state != initial_state
      assert new_state.poll_id == "test-poll-123"
      assert new_state.title == "Favorite Color?"
    end
    
    test "✅ EVENT TIMESTAMPS: uses event timestamps, not current time", %{initial_state: initial_state} do
      # Create event with specific timestamps
      specific_created_at = ~U[2024-06-15 14:30:00Z]
      specific_expires_at = ~U[2024-06-16 14:30:00Z]
      
      event = %EventV1{
        poll_id: "test-poll-456",
        title: "Test Poll",
        description: "A test poll",
        options: [
          %{id: "option_1", text: "Option A"},
          %{id: "option_2", text: "Option B"}
        ],
        created_by: "test-creator",
        expires_at: specific_expires_at,
        initialized_at: specific_created_at,
        version: 1
      }
      
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify timestamps are from event, not current time
      assert new_state.created_at == specific_created_at
      assert new_state.expires_at == specific_expires_at
    end
    
    test "correctly initializes all poll fields", %{event: event, initial_state: initial_state} do
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify basic fields
      assert new_state.poll_id == "test-poll-123"
      assert new_state.title == "Favorite Color?"
      assert new_state.description == "Choose your favorite color"
      assert new_state.created_by == "test-creator"
      assert new_state.status == :active
      assert new_state.created_at == ~U[2024-01-01 10:00:00Z]
      assert new_state.expires_at == ~U[2024-01-02 10:00:00Z]
      assert new_state.closed_at == nil
      assert new_state.version == 1
      
      # Verify options were stored correctly
      assert length(new_state.options) == 3
      
      option_1 = Enum.find(new_state.options, &(&1.id == "option_1"))
      option_2 = Enum.find(new_state.options, &(&1.id == "option_2"))
      option_3 = Enum.find(new_state.options, &(&1.id == "option_3"))
      
      assert option_1.text == "Red"
      assert option_2.text == "Blue"
      assert option_3.text == "Green"
      
      # Verify votes are initialized empty
      assert new_state.votes == %{}
    end
    
    test "handles poll without expiration", %{initial_state: initial_state} do
      # Create event without expiration
      event = %EventV1{
        poll_id: "test-poll-no-expiry",
        title: "Permanent Poll",
        description: "This poll never expires",
        options: [
          %{id: "option_1", text: "Yes"},
          %{id: "option_2", text: "No"}
        ],
        created_by: "test-creator",
        expires_at: nil,  # No expiration
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify no expiration was set
      assert new_state.expires_at == nil
      assert new_state.poll_id == "test-poll-no-expiry"
      assert new_state.title == "Permanent Poll"
    end
    
    test "handles poll without description", %{initial_state: initial_state} do
      # Create event without description
      event = %EventV1{
        poll_id: "test-poll-no-desc",
        title: "Simple Poll",
        description: nil,  # No description
        options: [
          %{id: "option_1", text: "Option A"}
        ],
        created_by: "test-creator",
        expires_at: nil,
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify no description was set
      assert new_state.description == nil
      assert new_state.poll_id == "test-poll-no-desc"
      assert new_state.title == "Simple Poll"
    end
    
    test "handles different option configurations", %{initial_state: initial_state} do
      # Create event with many options
      event = %EventV1{
        poll_id: "test-poll-many-options",
        title: "Rating Poll",
        description: "Rate from 1 to 5",
        options: [
          %{id: "option_1", text: "1 - Terrible"},
          %{id: "option_2", text: "2 - Bad"},
          %{id: "option_3", text: "3 - Okay"},
          %{id: "option_4", text: "4 - Good"},
          %{id: "option_5", text: "5 - Excellent"}
        ],
        created_by: "test-creator",
        expires_at: nil,
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify all options were stored
      assert length(new_state.options) == 5
      
      # Check each option
      option_ids = Enum.map(new_state.options, & &1.id)
      assert "option_1" in option_ids
      assert "option_2" in option_ids
      assert "option_3" in option_ids
      assert "option_4" in option_ids
      assert "option_5" in option_ids
      
      # Check specific option content
      option_5 = Enum.find(new_state.options, &(&1.id == "option_5"))
      assert option_5.text == "5 - Excellent"
    end
    
    test "handles minimum options (2)", %{initial_state: initial_state} do
      # Create event with exactly 2 options
      event = %EventV1{
        poll_id: "test-poll-binary",
        title: "Yes/No Poll",
        description: "Binary choice",
        options: [
          %{id: "option_1", text: "Yes"},
          %{id: "option_2", text: "No"}
        ],
        created_by: "test-creator",
        expires_at: nil,
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify both options were stored
      assert length(new_state.options) == 2
      
      option_ids = Enum.map(new_state.options, & &1.id)
      assert "option_1" in option_ids
      assert "option_2" in option_ids
      
      # Check content
      yes_option = Enum.find(new_state.options, &(&1.id == "option_1"))
      no_option = Enum.find(new_state.options, &(&1.id == "option_2"))
      
      assert yes_option.text == "Yes"
      assert no_option.text == "No"
    end
    
    test "initializes votes as empty map", %{event: event, initial_state: initial_state} do
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify votes are initialized as empty
      assert new_state.votes == %{}
      assert map_size(new_state.votes) == 0
    end
    
    test "handles edge case with empty string fields", %{initial_state: initial_state} do
      # Create event with empty strings
      event = %EventV1{
        poll_id: "test-poll-empty-strings",
        title: "",  # Empty title
        description: "",  # Empty description
        options: [
          %{id: "option_1", text: "Valid Option"}
        ],
        created_by: "",  # Empty creator
        expires_at: nil,
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      # Apply the event
      new_state = InitializedToStateV1.apply(initial_state, event)
      
      # Verify empty strings are preserved
      assert new_state.title == ""
      assert new_state.description == ""
      assert new_state.created_by == ""
      assert new_state.poll_id == "test-poll-empty-strings"
      
      # Options should still work
      assert length(new_state.options) == 1
      assert List.first(new_state.options).text == "Valid Option"
    end
    
    test "handles event version correctly", %{initial_state: initial_state} do
      # Create events with different versions
      event_v1 = %EventV1{
        poll_id: "test-poll-v1",
        title: "Version 1 Poll",
        description: "A version 1 poll",
        options: [
          %{id: "option_1", text: "Option A"}
        ],
        created_by: "test-creator",
        expires_at: nil,
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 1
      }
      
      event_v2 = %EventV1{
        poll_id: "test-poll-v2",
        title: "Version 2 Poll",
        description: "A version 2 poll",
        options: [
          %{id: "option_1", text: "Option A"}
        ],
        created_by: "test-creator",
        expires_at: nil,
        initialized_at: ~U[2024-01-01 10:00:00Z],
        version: 2
      }
      
      # Apply the events
      state_v1 = InitializedToStateV1.apply(initial_state, event_v1)
      state_v2 = InitializedToStateV1.apply(initial_state, event_v2)
      
      # Verify versions are stored correctly
      assert state_v1.version == 1
      assert state_v2.version == 2
    end
  end
end
