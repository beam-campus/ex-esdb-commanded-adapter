defmodule RegulateGreenhouse.Repo do
  use Ecto.Repo,
    otp_app: :regulate_greenhouse,
    adapter: Ecto.Adapters.SQLite3
end
