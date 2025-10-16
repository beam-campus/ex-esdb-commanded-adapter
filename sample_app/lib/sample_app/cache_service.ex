defmodule SampleApp.CacheService do
  @moduledoc false
  use Supervisor

  def key(store_id), do: Integer.to_string(:erlang.phash2({store_id}))

  def swarm_key(store_id), do: {:cache_service, key(store_id)}

  @impl true
  def init(_init_arg) do
    children = [
      Supervisor.child_spec(
        {Cachex, name: :poll_summaries, limit: 10_000},
        id: :poll_summaries_cache
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
