defmodule SampleApp.ReadModels.CacheSubscriberSystem do
  @moduledoc """
  Supervisor for all cache subscribers in the SampleApp domain.
  
  Manages the lifecycle of cache subscribers that listen to PubSub broadcasts
  and update read model caches.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      # Poll Results Cache Subscribers
      SampleApp.CastVote.CastedToPollResultsCacheV1,
      SampleApp.InitializePoll.InitializedToPollResultsCacheV1,
      SampleApp.ClosePoll.PollClosedToPollResultsCacheV1,
      SampleApp.ExpireCountdown.CountdownExpiredToPollResultsCacheV1,

      # Poll Summary Cache Subscribers
      SampleApp.InitializePoll.InitializedToPollSummaryCacheV1,
      SampleApp.ClosePoll.PollClosedToPollSummaryCacheV1,
      SampleApp.ExpireCountdown.CountdownExpiredToPollSummaryCacheV1,
      SampleApp.CastVote.CastedToPollSummaryCacheV1,

      # Voter History Cache Subscribers
      SampleApp.CastVote.CastedToVoterHistoryCacheV1
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Utility functions for managing subscribers
  def subscriber_status do
    Supervisor.which_children(__MODULE__)
    |> Enum.map(fn {module, pid, _type, _modules} ->
      {module, pid, if(Process.alive?(pid), do: :running, else: :stopped)}
    end)
  end

  def restart_subscriber(module) do
    case Supervisor.terminate_child(__MODULE__, module) do
      :ok ->
        case Supervisor.restart_child(__MODULE__, module) do
          {:ok, _pid} -> :ok
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end
end
