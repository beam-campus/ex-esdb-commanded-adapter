defmodule ExESDB.Commanded.ProjectionsRebuilderTest do
  use ExUnit.Case, async: false

  alias ExESDB.Commanded.ProjectionsRebuilder

  # Test projection modules
  defmodule TestProjection1 do
    use Commanded.Event.Handler,
      application: TestApp.CommandedApp,
      name: "test_projection_1"

    def init, do: :ok
    def handle(_event, _metadata), do: :ok
  end

  defmodule TestProjection2 do
    use Commanded.Event.Handler,
      application: TestApp.CommandedApp,
      name: "test_projection_2"

    def init, do: :ok
    def handle(_event, _metadata), do: :ok
  end

  # Mock CommandedApp for testing
  defmodule TestApp.CommandedApp do
    def stop_event_handler(_projection), do: :ok
    def reset_event_handler(_projection), do: :ok
    def start_event_handler(_projection, _opts), do: {:ok, self()}
  end

  setup do
    start_supervised!({ProjectionsRebuilder, application: TestApp.CommandedApp})
    :ok
  end

  describe "rebuild_projections/2" do
    test "successfully rebuilds valid projections" do
      projections = [TestProjection1, TestProjection2]

      assert {:ok, infos} = ProjectionsRebuilder.rebuild_projections(projections)
      assert length(infos) == 2

      for info <- infos do
        assert info.status == :completed
        assert info.error == nil
        assert info.started_at != nil
        assert info.completed_at != nil
      end
    end

    test "handles invalid projections" do
      projections = [TestProjection1, InvalidModule]

      assert {:error, {:invalid_projections, invalid}} = ProjectionsRebuilder.rebuild_projections(projections)

      assert invalid == ["InvalidModule"]
    end

    test "supports concurrent rebuilds" do
      projections = [TestProjection1, TestProjection2]
      opts = [concurrency: 2]

      assert {:ok, infos} = ProjectionsRebuilder.rebuild_projections(projections, opts)
      assert length(infos) == 2
    end

    test "respects timeout option" do
      # Mock slow projection
      defmodule SlowProjection do
        use Commanded.Event.Handler,
          application: TestApp.CommandedApp,
          name: "slow_projection"

        def init, do: Process.sleep(2000)
        def handle(_event, _metadata), do: :ok
      end

      assert {:error, _} = ProjectionsRebuilder.rebuild_projections([SlowProjection], timeout: 100)
    end
  end

  describe "rebuild_all/1" do
    test "rebuilds all discovered projections" do
      # This needs to be implemented once projection discovery is complete
      assert {:ok, []} = ProjectionsRebuilder.rebuild_all(application: TestApp.CommandedApp)
    end
  end

  describe "status/0" do
    test "returns current rebuild status" do
      projections = [TestProjection1]
      
      :ok = ProjectionsRebuilder.rebuild_projections(projections)
      status = ProjectionsRebuilder.status()

      assert %{projections: [info]} = status
      assert info.name == TestProjection1
      assert info.status == :completed
    end

    test "tracks failed rebuilds" do
      # Mock failing projection
      defmodule FailingProjection do
        use Commanded.Event.Handler,
          application: TestApp.CommandedApp,
          name: "failing_projection"

        def init, do: {:error, :test_failure}
        def handle(_event, _metadata), do: :ok
      end

      {:error, _} = ProjectionsRebuilder.rebuild_projections([FailingProjection])
      status = ProjectionsRebuilder.status()

      assert %{projections: [info]} = status
      assert info.name == FailingProjection
      assert info.status == :failed
      assert info.error != nil
    end
  end
end

