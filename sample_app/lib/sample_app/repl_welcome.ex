defmodule SampleApp.REPLWelcome do
  @moduledoc """
  Welcome message and setup for REPL usage.
  
  This module provides a friendly welcome message and sets up
  convenient aliases for interactive use.
  """
  
  @doc """
  Shows the welcome message and sets up helpful aliases.
  """
  def welcome do
    IO.puts("""
    
    🎉 Welcome to SampleApp - Event-Sourced Voting System! 🗳️
    ========================================================
    
    This application demonstrates a complete business domain built with:
    ✨ Event Sourcing using ExESDB
    ✨ CQRS with Commanded
    ✨ Domain-Driven Design patterns
    ✨ Vertical slicing architecture
    
    Quick Start:
    -----------
    
    # Set up convenient alias
    alias SampleApp.VotingREPL, as: Voting
    
    # Get help
    Voting.help()
    
    # Create your first poll
    Voting.create_poll("Favorite Programming Language?", ["Elixir", "Rust", "Go"])
    
    # Vote on it
    Voting.vote("poll-123", "option_1", "alice")
    
    # See your polls
    Voting.list_polls()
    
    Happy voting! 🗳️✨
    
    """)
    
    # Return a helpful reminder
    """
    💡 Quick tip: Run `Voting.help()` for all available commands!
    
    To get started:
      alias SampleApp.VotingREPL, as: Voting
      Voting.help()
    """
  end
  
  @doc """
  Sets up convenient aliases for REPL use.
  """
  defmacro setup_aliases do
    quote do
      alias SampleApp.VotingREPL, as: Voting
      alias SampleApp.CommandedApp
      alias SampleApp.Shared.Poll
    end
  end
  
  @doc """
  Quick demo of the voting system.
  """
  def demo do
    alias SampleApp.VotingREPL, as: Voting
    
    IO.puts("🎬 Running a quick demo of the voting system...")
    IO.puts("")
    
    # Create a poll
    IO.puts("1️⃣ Creating a poll...")
    {:ok, poll_id} = Voting.create_poll("Demo: Best Beverage?", ["Coffee", "Tea", "Water"], "demo_user")
    
    Process.sleep(500)
    
    # Cast some votes
    IO.puts("\n2️⃣ Casting some votes...")
    Voting.vote(poll_id, "option_1", "alice")
    Process.sleep(200)
    
    Voting.vote(poll_id, "option_2", "bob")
    Process.sleep(200)
    
    Voting.vote(poll_id, "option_1", "charlie")
    Process.sleep(200)
    
    # Try to vote twice (should fail)
    IO.puts("\n3️⃣ Trying to vote twice (should fail)...")
    Voting.vote(poll_id, "option_3", "alice")
    
    Process.sleep(500)
    
    # Show poll info
    IO.puts("\n4️⃣ Poll information:")
    Voting.poll_info(poll_id)
    
    # Create a poll with expiration
    IO.puts("\n5️⃣ Creating a poll with expiration...")
    {:ok, expire_poll_id} = Voting.create_poll_with_expiration("Quick Poll", ["Yes", "No"], 10, "demo_user")
    
    Process.sleep(500)
    
    # Close the first poll
    IO.puts("\n6️⃣ Closing the first poll...")
    Voting.close_poll(poll_id, "demo_user")
    
    Process.sleep(500)
    
    # List all polls
    IO.puts("\n7️⃣ All polls in this session:")
    Voting.list_polls()
    
    IO.puts("\n🎉 Demo complete! The expiring poll will expire in 10 seconds.")
    IO.puts("💡 Try: Voting.expire_poll(\"#{expire_poll_id}\") to manually expire it.")
    
    :demo_complete
  end
end
