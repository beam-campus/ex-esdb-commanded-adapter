defmodule Mix.Tasks.CacheRebuild do
  @moduledoc """
  Mix task to rebuild the greenhouse cache from ExESDB events.
  
  Usage:
    mix cache_rebuild
  """
  
  use Mix.Task
  
  require Logger
  
  @impl Mix.Task
  def run(_args) do
    # Start the application dependencies
    Mix.Task.run("app.start")
    
    Logger.info("Starting cache rebuild process...")
    
    case RegulateGreenhouse.CacheRebuildService.rebuild_cache() do
      {:ok, stats} ->
        Logger.info("Cache rebuild completed successfully!")
        Logger.info("Statistics: #{inspect(stats)}")
        :ok
        
      {:error, reason} ->
        Logger.error("Cache rebuild failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
