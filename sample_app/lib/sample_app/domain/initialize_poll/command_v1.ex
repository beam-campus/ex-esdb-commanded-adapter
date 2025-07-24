defmodule SampleApp.Domain.InitializePoll.CommandV1 do
  @moduledoc """
  Command to initialize a new poll with multiple voting options.
  
  This command is triggered when a user wants to create a new poll
  with specific options and an optional expiration time.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :title,
    :description,
    :options,
    :created_by,
    :expires_at,
    :requested_at
  ]
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    title: String.t(),
    description: String.t() | nil,
    options: [String.t()],
    created_by: String.t(),
    expires_at: DateTime.t() | nil,
    requested_at: DateTime.t()
  }
  
  @doc """
  Creates a new InitializePoll command.
  """
  def new(attrs) do
    struct(__MODULE__, attrs)
  end
  
  @doc """
  Validates the command according to business rules.
  """
  def valid?(%__MODULE__{} = command) do
    with :ok <- validate_poll_id(command.poll_id),
         :ok <- validate_title(command.title),
         :ok <- validate_options(command.options),
         :ok <- validate_created_by(command.created_by),
         :ok <- validate_expires_at(command.expires_at) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_poll_id(nil), do: {:error, :poll_id_required}
  defp validate_poll_id(""), do: {:error, :poll_id_required}
  defp validate_poll_id(_), do: :ok
  
  defp validate_title(nil), do: {:error, :title_required}
  defp validate_title(""), do: {:error, :title_required}
  defp validate_title(_), do: :ok
  
  defp validate_options(nil), do: {:error, :options_required}
  defp validate_options(options) when length(options) < 2, do: {:error, :minimum_two_options}
  defp validate_options(options) do
    if Enum.any?(options, &(&1 == "" or is_nil(&1))) do
      {:error, :empty_options_not_allowed}
    else
      :ok
    end
  end
  
  defp validate_created_by(nil), do: {:error, :created_by_required}
  defp validate_created_by(""), do: {:error, :created_by_required}
  defp validate_created_by(_), do: :ok
  
  defp validate_expires_at(nil), do: :ok
  defp validate_expires_at(expires_at) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :expiration_must_be_future}
    end
  end
end
