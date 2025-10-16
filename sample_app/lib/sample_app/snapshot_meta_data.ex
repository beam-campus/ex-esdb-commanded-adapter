defmodule SampleApp.SnapshotMetaData do
  @moduledoc false

  @enforce_keys [
    :version,
    :timestamp,
    :read_model,
    :checksum
  ]

  defstruct [
    :version,
    :timestamp,
    :read_model,
    :checksum
  ]

  @type t :: %__MODULE__{
          version: Integer.t(),
          timestamp: DateTime.t(),
          read_model: atom(),
          checksum: Integer.t()
        }

  def checksum(version, read_model, payload),
    do: :erlang.phash2({version, read_model, payload})

  def epoch(timestamp),
    do: DateTime.to_unix(timestamp, :millisecond)

  def new(version, read_model, payload) do
    timestamp = DateTime.utc_now()

    %__MODULE__{
      version: version,
      timestamp: timestamp,
      read_model: read_model,
      checksum: checksum(version, read_model, payload)
    }
  end
end
