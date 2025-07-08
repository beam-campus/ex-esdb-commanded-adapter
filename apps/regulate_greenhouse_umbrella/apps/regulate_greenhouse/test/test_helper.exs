ExUnit.start()

# Start required applications for testing in proper order
# ExESDB Gater must start before ExESDB since ExESDB depends on it
{:ok, _} = Application.ensure_all_started(:ex_esdb_gater)
{:ok, _} = Application.ensure_all_started(:ex_esdb)
{:ok, _} = Application.ensure_all_started(:commanded)

# Start the regulate_greenhouse application
{:ok, _} = Application.ensure_all_started(:regulate_greenhouse)

# Set up Ecto sandbox for database testing
if Code.ensure_loaded?(RegulateGreenhouse.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(RegulateGreenhouse.Repo, :manual)
end
