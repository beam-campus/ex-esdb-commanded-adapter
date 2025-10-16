defmodule SampleApp.CastVote.CastedToPollResultsCacheV1Test do
  use SampleApp.DataCase, async: false

  alias SampleApp.CastVote.CastedToPollResultsCacheV1
  alias SampleApp.ReadModels.PollResults

  describe "cache subscriber" do
    test "updates cache when vote casting event is received" do
      # Start the cache subscriber
      {:ok, _pid} = CastedToPollResultsCacheV1.start_link([])

      # Subscribe to cache updates
      Phoenix.PubSub.subscribe(SampleApp.PubSub, "poll_results_cache_updates")

      # Create partial read model (simulating PubSub message)
      read_model = %{
        poll_id: "poll-123",
        voter_id: "voter-456",
        choice: "choice-A",
        title: "Test Poll",
        casted_at: ~U[2024-01-01 10:00:00Z],
        updated_at: ~U[2024-01-01 10:00:00Z]
      }

      # Send the message to the subscriber
      send(CastedToPollResultsCacheV1, {:vote_casted, read_model})

      # Wait for processing
      :timer.sleep(100)

      # Verify cache was updated
      {:ok, cached_results} = Cachex.get(:poll_results, "poll-123")
      assert cached_results.poll_id == "poll-123"
      assert cached_results.title == "Test Poll"
      assert cached_results.total_votes == 1
      assert cached_results.status == :active
      
      [result] = cached_results.results
      assert result.option_id == "choice-A"
      assert result.vote_count == 1
      assert result.percentage == 100.0
      assert result.rank == 1
    end
  end
end
