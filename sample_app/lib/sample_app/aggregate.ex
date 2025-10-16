defmodule SampleApp.Aggregate do
  @moduledoc """
  Poll aggregate root for the voting system.
  
  Maintains the state of a single poll including its options, votes, and status.
  This aggregate enforces business rules around voting, poll creation, and closure.
  
  Following The Guidelines: There is exactly one aggregate per service, always named 'Aggregate'.
  """

  @derive Jason.Encoder
  defstruct [
    :poll_id,
    :title,
    :description,
    :options,      # List of %{id: String.t(), text: String.t()}
    :created_by,
    :expires_at,
    :status,       # :active | :closed | :expired
    :votes,        # Map of %{voter_id => option_id}
    :created_at,
    :closed_at,
    :expired_at,
    :version       # Version of the aggregate/event
  ]

  @type option :: %{id: String.t(), text: String.t()}
  @type status :: :active | :closed | :expired
  @type votes :: %{String.t() => String.t()}

  @type t :: %__MODULE__{
    poll_id: String.t() | nil,
    title: String.t() | nil,
    description: String.t() | nil,
    options: [option] | nil,
    created_by: String.t() | nil,
    expires_at: DateTime.t() | nil,
    status: status | nil,
    votes: votes | nil,
    created_at: DateTime.t() | nil,
    closed_at: DateTime.t() | nil,
    expired_at: DateTime.t() | nil,
    version: integer() | nil
  }

  @doc """
  Creates a new empty poll aggregate.
  """
  def new do
    %__MODULE__{
      votes: %{},
      status: nil
    }
  end

  @doc """
  Checks if the poll is active (can accept votes).
  """
  def active?(%__MODULE__{status: :active}), do: true
  def active?(_poll), do: false

  @doc """
  Checks if the poll is closed or expired.
  """
  def closed?(%__MODULE__{status: status}) when status in [:closed, :expired], do: true
  def closed?(_poll), do: false

  @doc """
  Checks if the poll has expired based on current time.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if a voter has already voted in this poll.
  """
  def voter_has_voted?(%__MODULE__{votes: votes}, voter_id) do
    Map.has_key?(votes, voter_id)
  end

  @doc """
  Checks if an option exists in this poll.
  """
  def option_exists?(%__MODULE__{options: options}, option_id) do
    Enum.any?(options, fn option -> option.id == option_id end)
  end

  @doc """
  Gets the total number of votes cast.
  """
  def total_votes(%__MODULE__{votes: votes}) do
    map_size(votes)
  end

  @doc """
  Gets vote counts by option.
  """
  def vote_counts(%__MODULE__{votes: votes}) do
    votes
    |> Map.values()
    |> Enum.frequencies()
  end

  @doc """
  Checks if the user is the creator of this poll.
  """
  def created_by?(%__MODULE__{created_by: created_by}, user_id) do
    created_by == user_id
  end

  # Command handlers - delegate to domain modules
  alias SampleApp.InitializePoll
  alias SampleApp.CastVote
  alias SampleApp.ClosePoll
  alias SampleApp.ExpireCountdown
  alias SampleApp.StartExpirationCountdown

  def execute_initialize_poll(poll, command) do
    InitializePoll.MaybeInitializePollV1.execute(poll, command)
  end

  def execute_cast_vote(poll, command) do
    CastVote.MaybeCastVoteV1.execute(poll, command)
  end

  def execute_close_poll(poll, command) do
    ClosePoll.MaybeClosePollV1.execute(poll, command)
  end

  def execute_expire_countdown(poll, command) do
    ExpireCountdown.MaybeExpireCountDownV1.execute(poll, command)
  end

  def execute_start_expiration_countdown(poll, command) do
    StartExpirationCountdown.MaybeStartExpirationCountdownV1.execute(poll, command)
  end

  # Event application functions - delegate to specific handlers
  alias SampleApp.InitializePoll.InitializedToAggregateV1
  alias SampleApp.CastVote.CastedToAggregateV1
  alias SampleApp.ClosePoll.ClosedToAggregateV1
  alias SampleApp.ExpireCountdown.ExpiredToAggregateV1
  alias SampleApp.StartExpirationCountdown.CountdownStartedToAggregateV1
  
  @doc """
  Applies events to the aggregate based on event type.
  """
  def apply(%__MODULE__{} = poll, %SampleApp.InitializePoll.EventV1{} = event) do
    InitializedToAggregateV1.apply(poll, event)
  end
  
  def apply(%__MODULE__{} = poll, %SampleApp.CastVote.EventV1{} = event) do
    CastedToAggregateV1.apply(poll, event)
  end
  
  def apply(%__MODULE__{} = poll, %SampleApp.ClosePoll.EventV1{} = event) do
    ClosedToAggregateV1.apply(poll, event)
  end
  
  def apply(%__MODULE__{} = poll, %SampleApp.ExpireCountdown.EventV1{} = event) do
    ExpiredToAggregateV1.apply(poll, event)
  end
  
  def apply(%__MODULE__{} = poll, %SampleApp.StartExpirationCountdown.EventV1{} = event) do
    CountdownStartedToAggregateV1.apply(poll, event)
  end
end
