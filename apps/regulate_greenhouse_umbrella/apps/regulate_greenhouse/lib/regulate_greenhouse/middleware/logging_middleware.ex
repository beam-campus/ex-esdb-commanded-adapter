defmodule RegulateGreenhouse.Middleware.LoggingMiddleware do
  @moduledoc """
  Middleware for logging command routing and execution.
  
  This middleware logs command routing, aggregate loading, and execution
  to help debug command handling issues.
  """
  
  @behaviour Commanded.Middleware
  
  require Logger
  
  def before_dispatch(%Commanded.Middleware.Pipeline{command: command} = pipeline) do
    command_name = command.__struct__ |> to_string() |> String.split(".") |> List.last()
    
    # Extract identity from command
    identity_value = case Map.get(command, :greenhouse_id) do
      nil -> "unknown"
      value -> value
    end
    
    Logger.info("Router: Routing #{command_name} command to aggregate #{identity_value}")
    Logger.debug("Router: Command details: #{inspect(command)}")
    
    pipeline
  end
  
  def after_dispatch(%Commanded.Middleware.Pipeline{command: command, response: response} = pipeline) do
    command_name = command.__struct__ |> to_string() |> String.split(".") |> List.last()
    
    # Extract identity from command
    identity_value = case Map.get(command, :greenhouse_id) do
      nil -> "unknown"
      value -> value
    end
    
    case response do
      events when is_list(events) ->
        event_count = length(events)
        Logger.info("Router: #{command_name} command completed for aggregate #{identity_value}, produced #{event_count} events")
        
        if event_count > 0 do
          event_types = events |> Enum.map(& &1.__struct__ |> to_string() |> String.split(".") |> List.last())
          Logger.info("Router: Events produced: #{inspect(event_types)}")
        end
      
      :ok ->
        Logger.info("Router: #{command_name} command completed for aggregate #{identity_value}")
      
      other ->
        Logger.info("Router: #{command_name} command completed for aggregate #{identity_value}, response: #{inspect(other)}")
    end
    
    pipeline
  end
  
  def after_failure(%Commanded.Middleware.Pipeline{command: command} = pipeline) do
    command_name = command.__struct__ |> to_string() |> String.split(".") |> List.last()
    
    # Extract identity from command
    identity_value = case Map.get(command, :greenhouse_id) do
      nil -> "unknown"
      value -> value
    end
    
    Logger.error("Router: #{command_name} command failed for aggregate #{identity_value}")
    
    pipeline
  end
end
