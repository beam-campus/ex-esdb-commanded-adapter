# IEx configuration for SampleApp Voting System
# This file is automatically loaded when starting `iex -S mix`

# Set up convenient aliases for the REPL
alias SampleApp.VotingREPL, as: Voting
alias SampleApp.REPLWelcome, as: Welcome
alias SampleApp.CommandedApp
alias SampleApp.Aggregates.Poll

# Show welcome message
Welcome.welcome()

# Helpful reminders for common patterns
IO.puts """

🚀 Ready to go! Common commands:
  Voting.help()                                    # Show all commands
  Voting.create_poll("Title", ["A", "B"])          # Create poll
  Voting.vote("poll-id", "option_1", "voter")     # Cast vote
  Voting.list_polls()                              # List polls
  Welcome.demo()                                   # Run full demo

📚 Learning more:
  The system uses Event Sourcing - all changes are stored as events!
  You can see events in the ExESDB logs as you interact with the system.

"""
