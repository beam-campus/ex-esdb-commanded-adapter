defmodule SampleApp.Schemas.PollSummary do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:poll_id, :string, autogenerate: false}
  schema "poll_summaries" do
    field :title, :string
    field :description, :string
    field :created_by, :string
    field :status, Ecto.Enum, values: [:active, :closed, :expired]
    field :total_votes, :integer, default: 0
    field :vote_counts, :map  # Using SQLite's JSON storage
    field :expires_at, :utc_datetime
    field :created_at, :utc_datetime
    field :closed_at, :utc_datetime
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [:poll_id, :title, :description, :created_by, :status, 
                    :total_votes, :vote_counts, :expires_at, :created_at, :closed_at])
    |> validate_required([:poll_id, :title, :created_by, :status, :total_votes, 
                         :vote_counts, :created_at])
  end
end
