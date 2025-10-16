defmodule SampleApp.ProjectionRebuildTest do
  use ExUnit.Case, async: false

  alias SampleApp.CommandedApp
  alias SampleApp.ReadModels.{PollSummary, PollResults}
  alias SampleApp.InitializePoll.CommandV1, as: InitializePollCommand

  @tag :rebuild
  test "rebuilds projections after cold start" do
    poll_id = "rebuild-test-#{System.unique_integer([:positive])}"

    # Step 1: Simulate cold start by clearing caches and stopping processes
    stop_all_subscribers()
    clear_all_caches()
    stop_commanded_app()

    # Step 2: Initialize projections and policies
    start_commanded_app()
    start_all_subscribers()

    # Step 3: Initialize a poll to generate events
    init_command = %InitializePollCommand{
      poll_id: poll_id,
      title: "Rebuild Test Poll",
      description: "Testing projection rebuild after cold start",
      options: ["Option 1", "Option 2"],
      created_by: "test-user",
      expires_at: nil,
      requested_at: DateTime.utc_now()
    }

    assert :ok = CommandedApp.dispatch(init_command)

    # Give time for projections to be rebuilt
    :timer.sleep(1000)

    # Step 4: Verify projections are rebuilt correctly
    {:ok, summary} = Cachex.get(:poll_summaries, poll_id)
    {:ok, results} = Cachex.get(:poll_results, poll_id)

    assert summary.poll_id == poll_id
    assert results.poll_id == poll_id
  end

  defp stop_all_subscribers do
    SampleApp.ReadModels.CacheSubscriberSystem
    |> Supervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)
  end

  defp start_all_subscribers do
    {:ok, _} = SampleApp.ReadModels.CacheSubscriberSystem.start_link(nil)
  end

  defp clear_all_caches do
    Cachex.clear!(:poll_summaries)
    Cachex.clear!(:poll_results)
  end

  defp stop_commanded_app do
    Application.stop(:sample_app)
  end

  defp start_commanded_app do
    Application.ensure_all_started(:sample_app)
  end
end

