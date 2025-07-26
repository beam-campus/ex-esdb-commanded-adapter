defmodule SampleApp.Domain.InitializePoll.InitializedToSummaryV1Test do
  use ExUnit.Case, async: true
  
  alias SampleApp.Domain.InitializePoll.{EventV1, InitializedToSummaryV1}
  alias SampleApp.ReadModels.PollSummary
  
  describe "InitializedToSummaryV1 projection" do
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
      
      {:ok, event: event}
    end
    
    test "✅ SELF-CONTAINED: only uses event data to create read model", %{event: event} do
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event
      result = InitializedToSummaryV1.handle(event, %{})
      
      # Should succeed
      assert result == :ok
      
      # Verify summary was created correctly
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-123")
      
      assert created_summary.poll_id == "test-poll-123"
      assert created_summary.title == "Favorite Color?"
      assert created_summary.description == "Choose your favorite color"
      assert created_summary.created_by == "test-creator"
      assert created_summary.status == :active
      assert created_summary.total_votes == 0
      assert created_summary.expires_at == ~U[2024-01-02 10:00:00Z]
      assert created_summary.created_at == ~U[2024-01-01 10:00:00Z]
      assert created_summary.closed_at == nil
      
      # Vote counts should be initialized to 0 for all options
      assert created_summary.vote_counts["option_1"] == 0
      assert created_summary.vote_counts["option_2"] == 0
      assert created_summary.vote_counts["option_3"] == 0
      assert map_size(created_summary.vote_counts) == 3
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-123")
    end
    
    test "✅ EVENT TIMESTAMPS: uses event timestamps, not current time", %{} do
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
      
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event
      result = InitializedToSummaryV1.handle(event, %{})
      assert result == :ok
      
      # Verify timestamps are from event, not current time
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-456")
      
      assert created_summary.created_at == specific_created_at
      assert created_summary.expires_at == specific_expires_at
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-456")
    end
    
    test "handles poll without expiration", %{} do
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
      
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event
      result = InitializedToSummaryV1.handle(event, %{})
      assert result == :ok
      
      # Verify summary was created with no expiration
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-no-expiry")
      
      assert created_summary.expires_at == nil
      assert created_summary.poll_id == "test-poll-no-expiry"
      assert created_summary.title == "Permanent Poll"
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-no-expiry")
    end
    
    test "handles poll without description", %{} do
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
      
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event
      result = InitializedToSummaryV1.handle(event, %{})
      assert result == :ok
      
      # Verify summary was created with no description
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-no-desc")
      
      assert created_summary.description == nil
      assert created_summary.poll_id == "test-poll-no-desc"
      assert created_summary.title == "Simple Poll"
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-no-desc")
    end
    
    test "✅ IDEMPOTENT: handles duplicate events gracefully", %{event: event} do
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event twice
      result1 = InitializedToSummaryV1.handle(event, %{})
      result2 = InitializedToSummaryV1.handle(event, %{})
      
      # Both should succeed
      assert result1 == :ok
      assert result2 == :ok
      
      # Verify only one summary exists
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-123")
      assert created_summary.poll_id == "test-poll-123"
      assert created_summary.total_votes == 0
      
      # The second event would overwrite the first (this is expected behavior for cache)
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-123")
    end
    
    test "handles different option configurations", %{} do
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
      
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event
      result = InitializedToSummaryV1.handle(event, %{})
      assert result == :ok
      
      # Verify all options were initialized with 0 votes
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-many-options")
      
      assert map_size(created_summary.vote_counts) == 5
      assert created_summary.vote_counts["option_1"] == 0
      assert created_summary.vote_counts["option_2"] == 0
      assert created_summary.vote_counts["option_3"] == 0
      assert created_summary.vote_counts["option_4"] == 0
      assert created_summary.vote_counts["option_5"] == 0
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-many-options")
    end
    
    test "handles minimum options (2)", %{} do
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
      
      # Start Cachex for testing - handle already started case
      case Cachex.start_link(:poll_summaries) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Process the event
      result = InitializedToSummaryV1.handle(event, %{})
      assert result == :ok
      
      # Verify both options were initialized
      {:ok, created_summary} = Cachex.get(:poll_summaries, "test-poll-binary")
      
      assert map_size(created_summary.vote_counts) == 2
      assert created_summary.vote_counts["option_1"] == 0
      assert created_summary.vote_counts["option_2"] == 0
      
      # Clean up
      Cachex.del(:poll_summaries, "test-poll-binary")
    end
    
    test "handles error scenarios gracefully", %{event: event} do
      # Ensure cache is not running for this test
      # Try to stop it if it exists, but don't fail if it doesn't work
      case Process.whereis(:poll_summaries) do
        nil -> :ok  # Already stopped
        pid -> 
          try do
            GenServer.stop(pid, :normal, 100)
          catch
            :exit, _ -> :ok  # Expected if process is already stopping
          end
          # Wait a bit to ensure it's fully stopped
          Process.sleep(50)
      end
      
      # Process the event (should fail gracefully when cache is unavailable)
      result = InitializedToSummaryV1.handle(event, %{})
      
      # Should return error
      assert {:error, _reason} = result
    end
  end
end
