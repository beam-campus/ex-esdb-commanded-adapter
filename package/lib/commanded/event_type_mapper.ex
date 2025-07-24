# New file: lib/commanded/event_type_mapper.ex
defmodule ExESDB.Commanded.EventTypeMapper do
  @moduledoc """
  Behaviour that defines how event modules are mapped to event type strings.

  Implementers must provide the to_event_type/1 function that converts
  an event module atom to a string representation.
  """

  @type t() :: module()

  @callback to_event_type(event_module :: module()) :: String.t()
end
