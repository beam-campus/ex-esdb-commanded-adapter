#!/usr/bin/env elixir

# Test script to initialize greenhouse "bob" and verify it works
# This script will:
# 1. Check if "bob" exists
# 2. Initialize "bob" if it doesn't exist
# 3. Try to set temperature for "bob"
# 4. Verify the command worked

IO.puts("=== Testing Greenhouse 'bob' ===")

# Check current greenhouse list
IO.puts("Current greenhouses:")
greenhouses = RegulateGreenhouse.API.list_greenhouses()
IO.inspect(greenhouses)

# Check if bob exists
bob_exists = "bob" in greenhouses
IO.puts("Does 'bob' exist? #{bob_exists}")

# If bob doesn't exist, initialize it
if not bob_exists do
  IO.puts("Initializing greenhouse 'bob'...")
  
  result = RegulateGreenhouse.API.initialize_greenhouse("bob", 25.0, 60.0, 500.0)
  IO.puts("Initialize result: #{inspect(result)}")
  
  # Wait a moment for the event to be processed
  Process.sleep(1000)
  
  # Check greenhouse list again
  IO.puts("Greenhouses after initialization:")
  greenhouses_after = RegulateGreenhouse.API.list_greenhouses()
  IO.inspect(greenhouses_after)
end

# Now try to set temperature for bob
IO.puts("Setting temperature for 'bob' to 22.5°C...")
temp_result = RegulateGreenhouse.API.set_temperature("bob", 22.5)
IO.puts("Set temperature result: #{inspect(temp_result)}")

# Get greenhouse state to verify
IO.puts("Getting greenhouse state for 'bob'...")
state_result = RegulateGreenhouse.API.get_greenhouse_state("bob")
IO.puts("Greenhouse state: #{inspect(state_result)}")

IO.puts("=== Test Complete ===")
