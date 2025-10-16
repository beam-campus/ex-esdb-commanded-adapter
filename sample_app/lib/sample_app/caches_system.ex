defmodule SampleApp.CachesSystem do
  @moduledoc false
  use Supervisor

  @impl true
  def init(_init_arg) do
    children = [
      Supervisor.child_spec(
        {Cachex, name: :poll_summaries, limit: 10_000},
        id: :poll_summaries_cache
      ),
      Supervisor.child_spec(
        {Cachex, name: :poll_results, limit: 10_000},
        id: :poll_results_cache
      ),
      Supervisor.child_spec(
        {Cachex, name: :voter_histories, limit: 10_000},
        id: :voter_histories_cache
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
end
