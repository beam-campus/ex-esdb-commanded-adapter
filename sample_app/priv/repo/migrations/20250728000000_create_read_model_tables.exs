defmodule SampleApp.Repo.Migrations.CreateReadModelTables do
  use Ecto.Migration

  def up do
    # Poll Summaries
    create table(:poll_summaries, primary_key: false) do
      add :poll_id, :string, primary_key: true
      add :title, :string, null: false
      add :description, :string
      add :created_by, :string, null: false
      add :status, :string, null: false, comment: "Must be one of: active, closed, expired"
      add :total_votes, :integer, null: false, default: 0
      add :vote_counts, :map, null: false  # JSON storage
      add :expires_at, :utc_datetime
      add :created_at, :utc_datetime, null: false
      add :closed_at, :utc_datetime
    end

    # Poll Results
    create table(:poll_results, primary_key: false) do
      add :poll_id, :string, primary_key: true
      add :title, :string, null: false
      add :total_votes, :integer, null: false, default: 0
      add :results, :map, null: false  # JSON array
      add :status, :string, null: false, comment: "Must be one of: active, closed, expired"
      add :closed_at, :utc_datetime
      add :created_at, :utc_datetime, null: false
      add :winner, :map  # JSON object
    end

    # Voter Histories
    create table(:voter_histories, primary_key: false) do
      add :voter_id, :string, primary_key: true
      add :poll_votes, :map, null: false  # JSON array
      add :last_vote_at, :utc_datetime
      add :total_votes_cast, :integer, null: false, default: 0
    end

    # Indexes
    create index(:poll_summaries, [:created_at])
    create index(:poll_summaries, [:status])
    create index(:poll_results, [:created_at])
    create index(:poll_results, [:status])
    create index(:voter_histories, [:last_vote_at])
  end

  def down do
    drop table(:poll_summaries)
    drop table(:poll_results)
    drop table(:voter_histories)
  end
end
