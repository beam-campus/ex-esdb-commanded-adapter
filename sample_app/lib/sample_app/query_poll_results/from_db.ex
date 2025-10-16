defmodule SampleApp.QueryPollResults.FromDB do
  @moduledoc """
  Database implementation for poll results queries.
  """
  import Ecto.Query
  alias SampleApp.{Repo, Schemas}
  require Logger

  @doc """
  Gets poll results by poll ID.
  """
  def get_poll_results(poll_id) do
    case Repo.get(Schemas.PollResults, poll_id) do
      nil -> {:error, :not_found}
      results -> {:ok, to_read_model(results)}
    end
  end

  @doc """
  Gets results for all closed polls.
  """
  def list_closed_poll_results do
    Schemas.PollResults
    |> where([p], p.status == :closed)
    |> order_by([p], desc: p.closed_at)
    |> Repo.all()
    |> Enum.map(&to_read_model/1)
  end

  @doc """
  Gets results for a specific voter's polls.
  """
  def get_results_by_voter(voter_id) do
    case Repo.get(Schemas.VoterHistory, voter_id) do
      nil -> []
      history ->
        poll_ids = Enum.map(history.poll_votes, & &1.poll_id)
        Schemas.PollResults
        |> where([p], p.poll_id in ^poll_ids)
        |> order_by([p], desc: p.created_at)
        |> Repo.all()
        |> Enum.map(&to_read_model/1)
    end
  end

  # Convert schema to read model
  defp to_read_model(schema) do
    schema
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> then(&struct(SampleApp.ReadModels.PollResults, &1))
  end
end
