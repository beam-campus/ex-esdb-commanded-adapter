defmodule SampleApp.QueryVoterHistory.FromDB do
  @moduledoc """
  Database implementation for voter history queries.
  """
  alias SampleApp.{Repo, Schemas}
alias SampleApp.Aggregates.Poll
  import Ecto.Query
  require Logger

  @doc """
  Gets a voter's history by ID.
  """
  def get_voter_history(voter_id) do
    case Repo.get(Schemas.VoterHistory, voter_id) do
      nil -> {:error, :not_found}
      history -> {:ok, to_read_model(history)}
    end
  end

  @doc """
  Checks if a voter has voted in a specific poll.
  """
  def has_voter_voted?(voter_id, poll_id) do
    case get_voter_history(voter_id) do
      {:ok, history} -> 
        Map.has_key?(history.votes, poll_id)
      {:error, :not_found} ->
        false
    end
  end

  # Convert schema to read model
  defp to_read_model(schema) do
    schema
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> then(&struct(SampleApp.ReadModels.VoterHistory, &1))
  end

  @doc """
  Gets poll summary from the database by poll_id.
  """
  def get_poll_summary(poll_id) do
    case Repo.get(Poll, poll_id) do
      nil -> {:error, :not_found}
      poll -> {:ok, poll}
    end
  end

  @doc """
  Gets poll results from the database by poll_id.
  """
  def get_poll_results(poll_id) do
    Repo.get(Poll, poll_id)
    |> case do
      nil -> {:error, :not_found}
      poll -> {:ok, poll}
    end
  end

  @doc """
  Lists all poll summaries from the database.
  """
  def list_all_poll_summaries do
    Repo.all(Poll)
  end

  @doc """
  Lists active polls from the database.
  """
  def list_active_polls do
    from(p in Poll, where: p.status == :active)
    |> Repo.all()
  end
end
