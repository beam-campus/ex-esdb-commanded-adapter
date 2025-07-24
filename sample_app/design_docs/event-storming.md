# Event Storming: Voting Process

## Overview

This document captures the event storming session for implementing a simple voting process in the sample application. Following the vertical slicing architecture principles, we'll identify business operations, commands, events, and their relationships.

## Domain: Voting System

### Business Operations (Vertical Slices)

#### 1. Initialize Poll
**Intent**: Allow users to initialize a new poll with multiple options

- **Command**: `InitializePoll`
  - `poll_id`: String
  - `title`: String
  - `description`: String (optional)
  - `options`: List of strings
  - `created_by`: String (user_id)
  - `expires_at`: DateTime (optional)
  - `requested_at`: DateTime

- **Event**: `PollInitialized`
  - `poll_id`: String
  - `title`: String
  - `description`: String (optional)
  - `options`: List of option structs `%{id: String, text: String}`
  - `created_by`: String
  - `expires_at`: DateTime (optional)
  - `created_at`: DateTime

- **Business Rules**:
  - Poll must have at least 2 options
  - Poll must have a title
  - Options cannot be empty strings
  - Expiration date must be in the future (if provided)
  - Poll ID must be unique

#### 2. Cast Vote
**Intent**: Allow users to vote on a poll option

- **Command**: `CastVote`
  - `poll_id`: String
  - `option_id`: String
  - `voter_id`: String
  - `requested_at`: DateTime

- **Event**: `VoteCasted`
  - `poll_id`: String
  - `option_id`: String
  - `voter_id`: String
  - `voted_at`: DateTime

- **Business Rules**:
  - Poll must exist and be active
  - Poll must not be expired
  - User can only vote once per poll
  - Option must exist in the poll
  - Voter ID must be provided

#### 3. Close Poll
**Intent**: Manually close a poll before its expiration time

- **Command**: `ClosePoll`
  - `poll_id`: String
  - `closed_by`: String (user_id)
  - `reason`: String (optional)
  - `requested_at`: DateTime

- **Event**: `PollClosed`
  - `poll_id`: String
  - `closed_by`: String
  - `reason`: String (optional)
  - `closed_at`: DateTime

- **Business Rules**:
  - Poll must exist and be active
  - Only the poll creator can close the poll manually
  - Cannot close an already closed poll

#### 4. Start Expiration Countdown (Automated Process)
**Intent**: Begin the expiration countdown for polls that have been initialized with an expiration time

- **Command**: `StartExpirationCountdown`
  - `poll_id`: String
  - `expires_at`: DateTime
  - `started_at`: DateTime

- **Event**: `ExpirationCountdownStarted`
  - `poll_id`: String
  - `expires_at`: DateTime
  - `started_at`: DateTime

- **Business Rules**:
  - Poll must exist and be active
  - Poll must have an expiration time set
  - Countdown can only be started once per poll
  - Expiration time must be in the future

#### 5. Expire Countdown (Automated Process)
**Intent**: Signal that a poll's expiration countdown has reached its end

- **Command**: `ExpireCountdown`
  - `poll_id`: String
  - `expired_at`: DateTime

- **Event**: `CountdownExpired`
  - `poll_id`: String
  - `expired_at`: DateTime

- **Business Rules**:
  - Poll must exist and have an active countdown
  - Current time must be at or past the expiration time
  - Poll must still be active (not already closed)

## Aggregate: Poll

The Poll aggregate will maintain the state of a single poll, including its options, votes, and status.

### Aggregate State
```elixir
defstruct [
  :poll_id,
  :title,
  :description,
  :options,      # List of %{id: String, text: String}
  :created_by,
  :expires_at,
  :status,       # :active | :closed | :expired
  :votes,        # Map of %{voter_id => option_id}
  :created_at,
  :closed_at
]
```

### State Transitions

1. **PollInitialized** → Initialize aggregate with poll details
2. **VoteCasted** → Add vote to votes map
3. **PollClosed** → Set status to :closed, set closed_at
4. **ExpirationCountdownStarted** → Set expiration tracking in aggregate
5. **CountdownExpired** → Mark countdown as expired in aggregate

## Read Models (Projections)

### 1. PollSummary
**Purpose**: Display basic poll information and current vote counts

Fields:
- `poll_id`
- `title`
- `description`
- `created_by`
- `status`
- `total_votes`
- `vote_counts` (map of option_id to count)
- `expires_at`
- `created_at`
- `closed_at`

### 2. PollResults  
**Purpose**: Detailed results view with percentages and voter information

Fields:
- `poll_id`
- `title`
- `total_votes`
- `results` (list of option results with counts and percentages)
- `status`
- `closed_at`

### 3. VoterHistory
**Purpose**: Track which polls a user has voted in

Fields:
- `voter_id`
- `poll_votes` (list of poll_id and option_id pairs)
- `last_vote_at`

## Policies (Process Managers)

### 1. Start Expiration Countdown Policy
**Trigger**: `PollInitialized` event (when poll has expiration time)
**Action**: Dispatch `StartExpirationCountdown` command when a poll with expiration is initialized

Location: `start_expiration_countdown/when_poll_initialized_then_start_expiration_countdown.ex`

### 2. Auto-Close Poll Policy  
**Trigger**: `CountdownExpired` event
**Action**: Dispatch `ClosePoll` command when countdown expires

Location: `close_poll/when_countdown_expired_then_close_poll.ex`

## File Structure (Following Guidelines)

```
lib/sample_app/domain/
├── initialize_poll/
│   ├── command.ex                    # InitializePoll command
│   ├── event.ex                      # PollInitialized event  
│   ├── maybe_initialize_poll.ex      # Command handler
│   ├── initialized_to_state.ex       # Event handler (aggregate update)
│   ├── initialized_to_summary.ex     # Projection to PollSummary
│   └── initialized_to_results.ex     # Projection to PollResults
├── cast_vote/
│   ├── command.ex                    # CastVote command
│   ├── event.ex                      # VoteCasted event
│   ├── maybe_cast_vote.ex            # Command handler  
│   ├── casted_to_state.ex            # Event handler
│   ├── casted_to_summary.ex          # Projection to PollSummary
│   ├── casted_to_results.ex          # Projection to PollResults
│   └── casted_to_voter_history.ex    # Projection to VoterHistory
├── close_poll/
│   ├── command.ex                    # ClosePoll command
│   ├── event.ex                      # PollClosed event
│   ├── maybe_close_poll.ex           # Command handler
│   ├── closed_to_state.ex            # Event handler
│   ├── closed_to_summary.ex          # Projection to PollSummary
│   └── when_countdown_expired_then_close_poll.ex  # Policy for auto-close
├── start_expiration_countdown/
│   ├── command.ex                    # StartExpirationCountdown command
│   ├── event.ex                      # ExpirationCountdownStarted event
│   ├── maybe_start_expiration_countdown.ex  # Command handler
│   ├── countdown_started_to_state.ex # Event handler
│   ├── countdown_started_to_summary.ex # Projection to PollSummary
│   └── when_poll_initialized_then_start_expiration_countdown.ex  # Policy
└── expire_countdown/
    ├── command.ex                    # ExpireCountdown command
    ├── event.ex                      # CountdownExpired event
    ├── maybe_expire_countdown.ex     # Command handler
    ├── expired_to_state.ex           # Event handler
    └── expired_to_summary.ex         # Projection to PollSummary
```

## Event Flow Examples

### Happy Path: Creating and Voting on a Poll

1. User creates a poll → `CreatePoll` command → `PollCreated` event
2. Multiple users vote → `CastVote` commands → `VoteCasted` events
3. Poll expires automatically → `ExpirePoll` command → `PollExpired` event

### Alternative Path: Manual Poll Closure

1. User creates a poll → `CreatePoll` command → `PollCreated` event  
2. Some users vote → `CastVote` commands → `VoteCasted` events
3. Creator closes poll early → `ClosePoll` command → `PollClosed` event

## Business Invariants

1. **One Vote Per User**: Each voter_id can only appear once in a poll's votes map
2. **Valid Options**: Votes can only be cast for options that exist in the poll
3. **Active Poll Required**: Votes can only be cast on active polls
4. **Creator Permissions**: Only poll creators can manually close their polls
5. **Expiration Logic**: Polls with expiration dates must be expired when the time passes
6. **Minimum Options**: Polls must have at least 2 options to be valid

## Next Steps

1. Implement the Poll aggregate in `lib/sample_app/shared/poll.ex`
2. Create each vertical slice following the structure above
3. Set up read model schemas in the database
4. Implement the poll expiration policy
5. Add tests for each slice
6. Create a simple UI for poll creation and voting

## Notes

- Following the `maybe_<command>.ex` naming convention for command handlers
- Each event handler updates the aggregate state (`*_to_state.ex`)
- Projections follow the `<event>_to_<readmodel>.ex` naming pattern  
- Policies are placed in the slice of the command they trigger
- Business events have meaningful names (PollCreated, VoteCasted) rather than CRUD names
