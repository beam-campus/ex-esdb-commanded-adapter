defmodule SampleApp.Schemas.VoterHistory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:voter_id, :string, autogenerate: false}
  schema "voter_histories" do
    field :poll_votes, :map     # JSON array of poll votes
    field :last_vote_at, :utc_datetime
    field :total_votes_cast, :integer, default: 0
  end

  def changeset(history, attrs) do
    history
    |> cast(attrs, [:voter_id, :poll_votes, :last_vote_at, :total_votes_cast])
    |> validate_required([:voter_id, :poll_votes, :total_votes_cast])
  end
end
