ExUnit.start()

# Start the ExESDB system for testing
Application.ensure_all_started(:ex_esdb_gater)

# Configure test environment
Application.put_env(:ex_esdb_commanded, :test_mode, true)
