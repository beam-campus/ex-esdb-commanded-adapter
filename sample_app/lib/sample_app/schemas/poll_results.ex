defmodule SampleApp.Schemas.PollResults do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:poll_id, :string, autogenerate: false}
  schema "poll_results" do
    field :title, :string
    field :total_votes, :integer, default: 0
    field :results, :map       # JSON array of option results
    field :status, Ecto.Enum, values: [:active, :closed, :expired]
    field :closed_at, :utc_datetime
    field :created_at, :utc_datetime
    field :winner, :map        # JSON object for winner
  end

  def changeset(results, attrs) do
    results
    |> cast(attrs, [:poll_id, :title, :total_votes, :results, :status, 
                    :closed_at, :created_at, :winner])
    |> validate_required([:poll_id, :title, :total_votes, :results, :status, 
                         :created_at])
  end
end
