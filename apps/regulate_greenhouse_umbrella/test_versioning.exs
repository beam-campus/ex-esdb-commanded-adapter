#!/usr/bin/env elixir

# Test script to verify 0-based versioning is working
# Run with: mix run test_versioning.exs

IO.puts("Testing 0-based versioning...")

try do
  IO.puts("Attempting to create a test greenhouse...")
  
  result = RegulateGreenhouse.API.initialize_greenhouse("test-0-based-versioning", 25.0, 50.0, 75.0)
  
  case result do
    :ok ->
      IO.puts("✅ SUCCESS: Greenhouse created successfully!")
      IO.puts("This confirms that 0-based versioning is working correctly.")
      
      # Try to list greenhouses
      IO.puts("\nTesting greenhouse listing...")
      greenhouses = RegulateGreenhouse.API.list_greenhouses()
      IO.puts("Found greenhouses: #{inspect(greenhouses)}")
      
    {:error, reason} ->
      IO.puts("❌ FAILED: #{inspect(reason)}")
      IO.puts("This suggests there may still be a versioning issue.")
  end
  
rescue
  error ->
    IO.puts("❌ ERROR: #{inspect(error)}")
    IO.puts("An unexpected error occurred.")
end

IO.puts("\nTest completed.")
