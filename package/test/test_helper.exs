ExUnit.start()

# Start the ExESDB system for testing
Application.ensure_all_started(:ex_esdb_gater)

# For integration tests, also start ExESDB
if System.get_env("INTEGRATION_TEST") do
  Application.ensure_all_started(:ex_esdb)
end

# Configure test environment
Application.put_env(:ex_esdb_commanded, :test_mode, true)

# Configure logger for tests
Logger.configure(level: :info)
