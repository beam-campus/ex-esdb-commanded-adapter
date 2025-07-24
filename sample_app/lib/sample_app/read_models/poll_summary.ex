defmodule SampleApp.ReadModels.PollSummary do
  @moduledoc """
  Read model for poll summary information.
  
  Provides basic poll information including title, status, vote counts,
  and timestamps for display in lists and overviews.
  """
  
  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :title,
    :description,
    :created_by,
    :status,
    :total_votes,
    :vote_counts,    # Map of option_id => count
    :expires_at,
    :created_at,
    :closed_at
  ]
  
  @type status :: :active | :closed | :expired
  
  @type t :: %__MODULE__{
    poll_id: String.t(),
    title: String.t(),
    description: String.t() | nil,
    created_by: String.t(),
    status: status(),
    total_votes: non_neg_integer(),
    vote_counts: %{String.t() => non_neg_integer()},
    expires_at: DateTime.t() | nil,
    created_at: DateTime.t(),
    closed_at: DateTime.t() | nil
  }
  
  @doc """
  Creates a new poll summary from initialization event.
  """
  def from_initialization(event) do
    %__MODULE__{
      poll_id: event.poll_id,
      title: event.title,
      description: event.description,
      created_by: event.created_by,
      status: :active,
      total_votes: 0,
      vote_counts: initialize_vote_counts(event.options),
      expires_at: event.expires_at,
      created_at: event.initialized_at,
      closed_at: nil
    }
  end
  
  @doc """
  Adds a vote to the summary.
  """
  def add_vote(%__MODULE__{} = summary, option_id) do
    new_vote_counts = Map.update(summary.vote_counts, option_id, 1, &(&1 + 1))
    
    %{summary |
      total_votes: summary.total_votes + 1,
      vote_counts: new_vote_counts
    }
  end
  
  @doc """
  Marks the poll as closed.
  """
  def close(%__MODULE__{} = summary, closed_at) do
    %{summary |
      status: :closed,
      closed_at: closed_at
    }
  end
  
  @doc """
  Marks the poll as expired.
  """
  def expire(%__MODULE__{} = summary, expired_at) do
    %{summary |
      status: :expired,
      closed_at: expired_at
    }
  end
  
  defp initialize_vote_counts(options) do
    options
    |> Enum.into(%{}, fn option -> {option.id, 0} end)
  end
end
