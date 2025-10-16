defmodule SampleApp.QueryPollResults.FromCache do
  @moduledoc """
  Public API for querying poll results read models.
  """

  alias SampleApp.ReadModels.PollResults

  @doc """
  Gets poll results by poll ID.
  """
  @spec get_poll_results(String.t()) :: {:ok, PollResults.t()} | {:error, :not_found}
  def get_poll_results(poll_id) do
    case Cachex.get(:poll_results, poll_id) do
      {:ok, %PollResults{} = results} -> {:ok, results}
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end
end
