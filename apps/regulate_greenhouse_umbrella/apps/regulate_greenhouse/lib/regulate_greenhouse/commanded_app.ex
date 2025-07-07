defmodule RegulateGreenhouse.CommandedApp do
  @moduledoc """
  Commanded application for RegulateGreenhouse.
  
  This module defines the Commanded application that uses the ExESDB.Commanded.Adapter
  for event sourcing with EventStore DB via the ExESDB Gater.
  """

  use Commanded.Application,
    otp_app: :regulate_greenhouse,
    event_store: [
      adapter: ExESDB.Commanded.Adapter,
      store_id: :reg_gh,
      stream_prefix: "regulate_greenhouse_"
    ],
    pubsub: [
      phoenix_pubsub: [
        name: RegulateGreenhouse.PubSub
      ]
    ],
    # Disable automatic subscriptions to prevent stream-based projections
    # We handle event subscriptions manually through the EventTypeProjectionManager
    subscribe_to_all_streams?: false,
    # Disable snapshotting to avoid version handling issues
    snapshotting: %{
      snapshot_every: nil
    }

  # Configure the event store adapter for command dispatch only
  router(RegulateGreenhouse.Router)
  
  @doc """
  Wrapper for Commanded.Application.dispatch/2 with logging.
  """
  def dispatch_command(command, opts \\ []) do
    require Logger
    command_name = command.__struct__ |> to_string() |> String.split(".") |> List.last()
    
    Logger.info("CommandedApp: Dispatching #{command_name} command: #{inspect(command)}")
    
    case Commanded.Application.dispatch(__MODULE__, command, opts) do
      :ok -> 
        Logger.info("CommandedApp: Successfully dispatched #{command_name} command")
        :ok
      {:error, reason} = error -> 
        Logger.error("CommandedApp: Failed to dispatch #{command_name} command: #{inspect(reason)}")
        error
    end
  end
end
