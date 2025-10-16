defmodule SampleApp.CastVote.CastedToPubSubV1Test do
  use SampleApp.DataCase, async: false

  alias SampleApp.CastVote.{EventV1, CastedToPubSubV1}

  describe "handle/2" do
    test "broadcasts vote casting event to PubSub" do
      # Subscribe to the PubSub topic
      Phoenix.PubSub.subscribe(SampleApp.PubSub, "poll_projections")

      event = %EventV1{
        poll_id: "poll-123",
        voter_id: "voter-456",
        choice: "choice-A",
        casted_at: ~U[2024-01-01 10:00:00Z]
      }

      # Process the event
      assert :ok = CastedToPubSubV1.handle(event, %{})

      # Verify PubSub message was received
      assert_receive {:vote_casted, read_model}
      assert read_model.poll_id == "poll-123"
      assert read_model.voter_id == "voter-456"
      assert read_model.choice == "choice-A"
      assert read_model.casted_at == ~U[2024-01-01 10:00:00Z]
    end
  end
end
