defmodule SampleApp.QueryPollSummary.FromDB do
  @moduledoc """
  Database implementation for poll summary queries.
  """
  import Ecto.Query
  alias SampleApp.{Repo, Schemas}
  require Logger

  @doc """
  Gets a poll summary by ID.
  """
  def get_poll_summary(poll_id) do
    case Repo.get(Schemas.PollSummary, poll_id) do
      nil -> {:error, :not_found}
      summary -> {:ok, to_read_model(summary)}
    end
  end

  @doc """
  Lists all poll summaries.
  """
  def list_all_poll_summaries do
    Schemas.PollSummary
    |> order_by([p], desc: p.created_at)
    |> Repo.all()
    |> Enum.map(&to_read_model/1)
  end

  @doc """
  Lists only active polls.
  """
  def list_active_polls do
    Schemas.PollSummary
    |> where([p], p.status == :active)
    |> order_by([p], desc: p.created_at)
    |> Repo.all()
    |> Enum.map(&to_read_model/1)
  end

  # Convert schema to read model
  defp to_read_model(schema) do
    schema
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> then(&struct(SampleApp.ReadModels.PollSummary, &1))
  end
end
