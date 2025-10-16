defmodule SampleApp.Aggregates.Poll do
  use Ecto.Schema

  @moduledoc """
  Poll schema representing poll data in the database.
  """

  schema "polls" do
    field :title, :string
    field :status, :string
    field :expires_at, :utc_datetime

    timestamps()
  end
end

