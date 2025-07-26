defmodule SampleApp.EventTypeMapper do
  @moduledoc """
  Event type mapper for converting Elixir module names to clean event type strings.

  This is required by the ExESDB.Commanded.Adapter to properly serialize
  and deserialize event types when storing and retrieving events.

  The mapper tries to call the `event_type/0` function on event modules to get
  clean semantic event types. If that fails, it falls back to using the module name.
  """

  @behaviour ExESDB.Commanded.EventTypeMapper
  @impl ExESDB.Commanded.EventTypeMapper
  def to_event_type(Elixir.SampleApp.Domain.CastVote.EventV1), do: "vote_casted:v1"
  def to_event_type(Elixir.SampleApp.Domain.ClosePoll.EventV1), do: "poll_closed:v1"
  def to_event_type(Elixir.SampleApp.Domain.CreatePoll.EventV1), do: "poll_created:v1"
  def to_event_type(Elixir.SampleApp.Domain.ExpireCountdown.EventV1), do: "countdown_expired:v1"
  def to_event_type(Elixir.SampleApp.Domain.InitializePoll.EventV1), do: "poll_initialized:v1"
  def to_event_type(Elixir.SampleApp.Domain.StartExpirationCountdown.EventV1), do: "countdown_started:v1"
  def to_event_type(event_type), do: to_string(event_type)
end
