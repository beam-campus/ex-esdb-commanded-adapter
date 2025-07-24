defmodule SampleApp.Domain.InitializePoll.EventV1 do
  @moduledoc """
  Event emitted when a poll is successfully initialized.
  
  This event contains all the information needed to track the poll's
  creation and triggers read model updates and other domain reactions.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :title,
    :description,
    :options,
    :created_by,
    :expires_at,
    :initialized_at,
    :version
  ]
  
  @type option :: %{id: String.t(), text: String.t()}
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    title: String.t(),
    description: String.t() | nil,
    options: [option],
    created_by: String.t(),
    expires_at: DateTime.t() | nil,
    initialized_at: DateTime.t(),
    version: integer()
  }
  
  @doc """
  Creates a new PollInitialized event from a command.
  """
  def from_command(%SampleApp.Domain.InitializePoll.CommandV1{} = command) do
    options = create_options_from_strings(command.options)
    
    %__MODULE__{
      poll_id: command.poll_id,
      title: command.title,
      description: command.description,
      options: options,
      created_by: command.created_by,
      expires_at: command.expires_at,
      initialized_at: command.requested_at,
      version: 1
    }
  end
  
  @doc """
  Gets the event type string for storage.
  """
  def event_type, do: "poll_initialized:v1"
  
  defp create_options_from_strings(option_strings) do
    option_strings
    |> Enum.with_index(1)
    |> Enum.map(fn {text, index} ->
      %{
        id: "option_#{index}",
        text: text
      }
    end)
  end
end
