defmodule SampleApp.TestDataGenerator do
  @moduledoc """
  Utility functions for generating random test data for polls and votes.
  """

  alias SampleApp.InitializePoll.CommandV1, as: InitializePollCommand
  alias SampleApp.CastVote.CommandV1, as: CastVoteCommand
  alias SampleApp.Router

  @doc """
  Generates and dispatches a specified number of random polls.
  Returns a list of poll IDs that were created.
  """
  def generate_random_polls(count \\ 5) do
    1..count
    |> Enum.map(fn _ -> generate_random_poll() end)
  end

  @doc """
  Generates and dispatches random votes for a given poll.
  Returns a list of the dispatched vote commands.
  """
  def generate_random_votes(poll_id, count \\ 10) do
    1..count
    |> Enum.map(fn _ -> generate_random_vote(poll_id) end)
  end

  @doc """
  Generates and dispatches both random polls and votes.
  Returns a map with the generated poll IDs and their corresponding votes.
  """
  def generate_random_polls_with_votes(poll_count \\ 5, votes_per_poll \\ 10) do
    poll_ids = generate_random_polls(poll_count)
    
    votes = Enum.map(poll_ids, fn poll_id ->
      {poll_id, generate_random_votes(poll_id, votes_per_poll)}
    end)
    |> Enum.into(%{})

    %{
      poll_ids: poll_ids,
      votes: votes
    }
  end

  # Private helpers

  defp generate_random_poll do
    poll_id = Ecto.UUID.generate()
    command = %InitializePollCommand{
      poll_id: poll_id,
      title: generate_random_title(),
      options: generate_random_options(),
      created_by: Ecto.UUID.generate(),
      expires_at: DateTime.add(DateTime.utc_now(), 300, :second),
      requested_at: DateTime.utc_now(),
      description: nil
    }

    Router.dispatch(command)
    poll_id
  end

  defp generate_random_vote(poll_id) do
    command = %CastVoteCommand{
      poll_id: poll_id,
      voter_id: Ecto.UUID.generate(),
      option_id: "option_#{Enum.random(0..2)}",
      requested_at: DateTime.utc_now()
    }

    Router.dispatch(command)
    command
  end

  defp generate_random_title do
    adjectives = ~w(Cool Amazing Interesting Exciting Fun Challenging Important Critical Basic Advanced)
    nouns = ~w(Poll Survey Question Topic Discussion Challenge Task Problem Project Test)
    
    adjective = Enum.random(adjectives)
    noun = Enum.random(nouns)
    
    "#{adjective} #{noun} #{random_string(4)}"
  end

  defp generate_random_options do
    options = [
      ~w(Yes No Maybe),
      ~w(Agree Disagree Neutral),
      ~w(Good Bad Unsure),
      ~w(High Medium Low),
      ~w(Red Blue Green)
    ]
    
    selected = Enum.random(options)
    
    selected
    |> Enum.with_index()
    |> Enum.map(fn {text, idx} ->
      option_id = "option_#{idx + 1}"
      %{id: option_id, text: %{id: option_id, text: text}}
    end)
  end

  defp random_string(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end
end
