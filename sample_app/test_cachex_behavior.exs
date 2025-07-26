#!/usr/bin/env elixir

# Test what happens when Cachex is not started
Mix.install([{:cachex, "~> 3.6"}])

IO.puts("Testing Cachex behavior when cache is not started...")

# Test 1: Try to use a cache that doesn't exist
IO.puts("\n1. Testing get_and_update on non-existent cache:")
result1 = Cachex.get_and_update(:nonexistent_cache, "test_key", fn 
  nil -> {:commit, "new_value"}
  existing -> {:commit, existing <> "_updated"}
end)
IO.inspect(result1, label: "Result")

# Test 2: Try to put to a non-existent cache
IO.puts("\n2. Testing put on non-existent cache:")
result2 = Cachex.put(:nonexistent_cache, "test_key", "test_value")
IO.inspect(result2, label: "Result")

# Test 3: Try to get from a non-existent cache
IO.puts("\n3. Testing get on non-existent cache:")
result3 = Cachex.get(:nonexistent_cache, "test_key")
IO.inspect(result3, label: "Result")

IO.puts("\n4. Testing with a started cache for comparison:")
{:ok, _pid} = Cachex.start_link(:test_cache)

result4 = Cachex.get_and_update(:test_cache, "test_key", fn 
  nil -> {:commit, "new_value"}
  existing -> {:commit, existing <> "_updated"}
end)
IO.inspect(result4, label: "Result with started cache")
