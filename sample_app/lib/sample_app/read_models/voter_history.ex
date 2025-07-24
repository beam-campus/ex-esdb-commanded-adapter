defmodule SampleApp.ReadModels.VoterHistory do
  @moduledoc """
  Read model for tracking voter history.
  
  Tracks which polls a user has voted in, what option they chose,
  and when they voted.
  """
  
  @derive Jason.Encoder
  defstruct [
    :voter_id,
    :poll_votes,    # List of poll vote records
    :last_vote_at,
    :total_votes_cast
  ]
  
  @type poll_vote :: %{
    poll_id: String.t(),
    option_id: String.t(),
    voted_at: DateTime.t()
  }
  
  @type t :: %__MODULE__{
    voter_id: String.t(),
    poll_votes: [poll_vote()],
    last_vote_at: DateTime.t() | nil,
    total_votes_cast: non_neg_integer()
  }
  
  @doc """
  Creates a new voter history record.
  """
  def new(voter_id) do
    %__MODULE__{
      voter_id: voter_id,
      poll_votes: [],
      last_vote_at: nil,
      total_votes_cast: 0
    }
  end
  
  @doc """
  Adds a vote to the voter's history.
  """
  def add_vote(%__MODULE__{} = history, poll_id, option_id, voted_at) do
    new_vote = %{
      poll_id: poll_id,
      option_id: option_id,
      voted_at: voted_at
    }
    
    %{history |
      poll_votes: [new_vote | history.poll_votes],
      last_vote_at: voted_at,
      total_votes_cast: history.total_votes_cast + 1
    }
  end
  
  @doc """
  Checks if the voter has already voted in a specific poll.
  """
  def has_voted?(%__MODULE__{} = history, poll_id) do
    Enum.any?(history.poll_votes, fn vote -> vote.poll_id == poll_id end)
  end
  
  @doc """
  Gets the voter's choice for a specific poll.
  """
  def get_vote(%__MODULE__{} = history, poll_id) do
    Enum.find(history.poll_votes, fn vote -> vote.poll_id == poll_id end)
  end
  
  @doc """
  Gets voting activity within a date range.
  """
  def votes_in_range(%__MODULE__{} = history, start_date, end_date) do
    history.poll_votes
    |> Enum.filter(fn vote ->
      DateTime.compare(vote.voted_at, start_date) != :lt and
      DateTime.compare(vote.voted_at, end_date) != :gt
    end)
  end
end
