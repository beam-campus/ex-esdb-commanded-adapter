defmodule SampleApp.QueryVoterHistory.FromCache do
  @moduledoc """
  Public API for querying voter history read models.
  """

  alias SampleApp.ReadModels.VoterHistory

  @doc """
  Gets voter history by voter ID.
  """
  @spec get_voter_history(String.t()) :: {:ok, VoterHistory.t()} | {:error, :not_found}
  def get_voter_history(voter_id) do
    case Cachex.get(:voter_histories, voter_id) do
      {:ok, %VoterHistory{} = history} -> {:ok, history}
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Checks if a voter has already voted in a specific poll.
  """
  @spec has_voter_voted?(String.t(), String.t()) :: boolean()
  def has_voter_voted?(voter_id, poll_id) do
    case get_voter_history(voter_id) do
      {:ok, history} -> VoterHistory.has_voted?(history, poll_id)
      {:error, :not_found} -> false
    end
  end
  @doc """
  Gets poll summary from the cache by poll_id.
  """
  @spec get_poll_summary(String.t()) :: {:ok, map()} | {:error, atom()}
  def get_poll_summary(poll_id) do
    case Cachex.get(:poll_summaries, poll_id) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, poll_summary} -> {:ok, poll_summary}
      error -> error
    end
  end

  @doc """
  Gets poll results from the cache by poll_id.
  """
  @spec get_poll_results(String.t()) :: {:ok, map()} | {:error, atom()}
  def get_poll_results(poll_id) do
    case Cachex.get(:poll_results, poll_id) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, poll_results} -> {:ok, poll_results}
      error -> error
    end
  end

  @doc """
  Lists all poll summaries from the cache.
  """
  @spec list_all_poll_summaries() :: list(map())
  def list_all_poll_summaries do
    Cachex.keys(:poll_summaries)
    |> Enum.map(&Cachex.get!(:poll_summaries, &1))
  end

  @doc """
  Lists active polls from the cache.
  """
  @spec list_active_polls() :: list(map())
  def list_active_polls do
    Cachex.keys(:poll_summaries)
    |> Enum.map(&Cachex.get!(:poll_summaries, &1))
    |> Enum.filter(fn poll -> poll[:status] == :active end)
  end
end
