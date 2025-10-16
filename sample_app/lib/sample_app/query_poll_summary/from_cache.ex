defmodule SampleApp.QueryPollSummary.FromCache do
  @moduledoc """
  Public API for querying poll summary read models.
  """

  alias SampleApp.ReadModels.PollSummary

  @doc """
  Gets a poll summary by poll ID.
  """
  @spec get_poll_summary(String.t()) :: {:ok, PollSummary.t()} | {:error, :not_found}
  def get_poll_summary(poll_id) do
    case Cachex.get(:poll_summaries, poll_id) do
      {:ok, %PollSummary{} = summary} -> {:ok, summary}
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Lists all poll summaries (for admin/debugging purposes).
  """
  @spec list_all_poll_summaries() :: {:ok, [PollSummary.t()]} | {:error, term()}
  def list_all_poll_summaries() do
    case Cachex.keys(:poll_summaries) do
      {:ok, keys} ->
        summaries =
          keys
          |> Enum.map(&get_poll_summary/1)
          |> Enum.filter(fn
            {:ok, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:ok, summary} -> summary end)

        {:ok, summaries}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Lists all active polls.
  """
  @spec list_active_polls() :: {:ok, [PollSummary.t()]} | {:error, term()}
  def list_active_polls() do
    case list_all_poll_summaries() do
      {:ok, summaries} ->
        active_polls = Enum.filter(summaries, fn summary -> summary.status == :active end)
        {:ok, active_polls}

      {:error, _reason} = error ->
        error
    end
  end
end
