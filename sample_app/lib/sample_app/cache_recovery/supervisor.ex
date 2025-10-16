defmodule SampleApp.CacheRecovery.Supervisor do
  @moduledoc """
  Supervisor for the cache recovery system.
  
  Manages the cache recovery manager and handles initialization
  of cache recovery on application startup.
  """
  use Supervisor

  alias SampleApp.{CacheRecovery.Manager, Schemas}

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [
      Manager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Registers the default caches for recovery.
  Should be called after the supervisor has started.
  """
  def register_default_caches do
    Manager.register_cache(:poll_summaries, Schemas.PollSummary)
    Manager.register_cache(:poll_results, Schemas.PollResults)
    Manager.register_cache(:voter_histories, Schemas.VoterHistory)
  end

  @doc """
  Recovers all registered caches from the database.
  Should be called after registering caches.
  """
  def recover_all do
    Manager.recover_all_caches()
  end
end
