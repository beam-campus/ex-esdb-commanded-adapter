defmodule ExESDB.Commanded.ProjectionsRebuilderIntegrationTest do
  use ExUnit.Case, async: false

  alias ExESDB.Commanded.ProjectionsRebuilder

  # Sample domain event
  defmodule TestEvent do
    @derive Jason.Encoder
    defstruct [:id, :data, :timestamp]
  end

  # Test projection that counts events
  defmodule CountingProjection do
    use Commanded.Event.Handler,
      application: TestApp.CommandedApp,
      name: "counting_projection"

    # Use an Agent to track state for testing
    def start_link(opts) do
      Agent.start_link(fn -> 0 end, Keyword.merge(opts, name: __MODULE__))
    end

    def get_count do
      Agent.get(__MODULE__, & &1)
    end

    def init do
      Agent.update(__MODULE__, fn _ -> 0 end)
      :ok
    end

    def handle(%TestEvent{}, _metadata) do
      Agent.update(__MODULE__, &(&1 + 1))
      :ok
    end
  end

  # Test application
  defmodule TestApp.CommandedApp do
    use Commanded.Application,
      otp_app: :ex_esdb_commanded,
      router: TestApp.Router,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    store_id: :test_store,
    stream_prefix: "test_",
    event_type_mapper: TestEventTypeMapper
  ],
  pub_sub: [
    adapter: Phoenix.PubSub.PG2
  ]
  end

  defmodule TestEventTypeMapper do
    @behaviour ExESDB.Commanded.EventTypeMapper

    @impl true
    def to_event_type(event_module) when is_atom(event_module) do
      event_module |> to_string() |> String.replace("Elixir.", "")
    end
  end

  # Test router
  defmodule TestApp.Router do
    use Commanded.Commands.Router

    identify TestEvent, by: :id
    dispatch TestEvent, to: CountingProjection
  end

  setup do
    # Start the test application and projection
    {:ok, _app} = TestApp.CommandedApp.start_link()
    {:ok, _proj} = CountingProjection.start_link()

    # Append some test events
    events = Enum.map(1..5, fn i ->
      %TestEvent{
        id: "event-#{i}",
        data: "test-#{i}",
        timestamp: DateTime.utc_now()
      }
    end)

    # Dispatch events
    for event <- events do
      :ok = TestApp.CommandedApp.dispatch(event)
    end

    # Wait for processing
    :timer.sleep(100)

    on_exit(fn ->
      :ok = TestApp.CommandedApp.stop()
    end)

    {:ok, %{events: events}}
  end

  describe "rebuild_projections/2" do
    test "rebuilds projection state from event store" do
      # Initial count should be 5 from setup
      assert CountingProjection.get_count() == 5

      # Stop and rebuild the projection
      :ok = TestApp.CommandedApp.stop_event_handler(CountingProjection)
      :ok = CountingProjection.init()  # Reset count to 0

      # Verify count is reset
      assert CountingProjection.get_count() == 0

      # Rebuild the projection
      assert {:ok, [info]} = ProjectionsRebuilder.rebuild_projections(
        [CountingProjection],
        application: TestApp.CommandedApp
      )

      # Wait for events to be replayed
      :timer.sleep(100)

      # Verify projection state is rebuilt
      assert CountingProjection.get_count() == 5
      assert info.status == :completed
      assert info.error == nil
    end

    test "handles projection rebuild failures gracefully" do
      # Create a failing projection
      defmodule FailingProjection do
        use Commanded.Event.Handler,
          application: TestApp.CommandedApp,
          name: "failing_projection"

        def start_link(opts) do
          Agent.start_link(fn -> 0 end, Keyword.merge(opts, name: __MODULE__))
        end
        
        def init, do: :ok

        # Simulate failure on second event
        def handle(%TestEvent{} = event, _metadata) do
          count = Agent.get(__MODULE__, & &1)
          Agent.update(__MODULE__, &(&1 + 1))

          if count == 1 do
            {:error, :simulated_failure}
          else
            :ok
          end
        end
      end

      {:ok, _} = FailingProjection.start_link()

      # Attempt to rebuild
      assert {:error, _reason} = ProjectionsRebuilder.rebuild_projections(
        [FailingProjection],
        application: TestApp.CommandedApp
      )

      # Verify status shows failure
      %{projections: [info]} = ProjectionsRebuilder.status()
      assert info.status == :failed
      assert info.error != nil
    end

    test "handles subscription streams and snapshots correctly" do
      # 1. Create events with snapshots
      events_with_snapshot = Enum.map(1..100, fn i ->
        %TestEvent{
          id: "event-#{i}",
          data: "test-#{i}",
          timestamp: DateTime.utc_now()
        }
      end)

      for event <- events_with_snapshot do
        :ok = TestApp.CommandedApp.dispatch(event)
      end

      # Wait for snapshot to be created
      :timer.sleep(200)

      # 2. Add more events after snapshot
      events_after_snapshot = Enum.map(101..150, fn i ->
        %TestEvent{
          id: "event-#{i}",
          data: "test-#{i}",
          timestamp: DateTime.utc_now()
        }
      end)

      for event <- events_after_snapshot do
        :ok = TestApp.CommandedApp.dispatch(event)
      end

      # Wait for processing
      :timer.sleep(100)

      # 3. Stop and rebuild the projection
      :ok = TestApp.CommandedApp.stop_event_handler(CountingProjection)
      :ok = CountingProjection.init()

      # 4. Rebuild with snapshot support
      assert {:ok, [info]} = ProjectionsRebuilder.rebuild_projections(
        [CountingProjection],
        application: TestApp.CommandedApp,
        use_snapshots: true
      )

      # Wait for rebuild
      :timer.sleep(200)

      # Verify all events were processed
      assert CountingProjection.get_count() == 150
      assert info.status == :completed
    end
  end
end
