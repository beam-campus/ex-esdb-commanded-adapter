defmodule SampleApp.SnapshotCache do
  @moduledoc """
  Behaviour defining the contract for cache recovery implementations.
  """

  @type read_model :: String.t()
  @type version :: non_neg_integer() | :origin
  @type snapshot :: %{
          data: term(),
          metadata: %{
            version: version(),
            timestamp: DateTime.t(),
            read_model: read_model()
          },
          checksum: binary()
        }

  @doc """
  Saves a Snapshot of the read_model to the backend snapshot store.
  Returns {:ok, snapshot} on success, {:error, reason} otherwise.
  """
  @callback(save_snapshot(read_model(), snapshot()) :: :ok, {:error, term()})

  @doc """
  Fetches the latest snapshot for the given read model.
  Returns {:ok, snapshot} if found, {:error, :no_snapshot} otherwise.
  """
  @callback fetch_latest_snapshot(read_model()) ::
              {:ok, snapshot()} | {:error, :no_snapshot} | {:error, term()}

  @doc """
  Validates the snapshot data integrity using its checksum.
  """
  @callback validate_snapshot(snapshot()) ::
              :ok | {:error, term()}

  @doc """
  Resets the projection to start from the given version.
  For :origin, replays from the beginning of the event stream.
  """
  @callback reset_projection(read_model(), version()) ::
              :ok | {:error, term()}

  @doc """
  Restores the cache state from the snapshot data.
  """
  @callback restore_from_snapshot(read_model(), term()) ::
              :ok | {:error, term()}

  @doc """
  Optional callback for computing checksum of snapshot data.
  Default implementation uses :crypto.hash(:sha256, :erlang.term_to_binary(data))
  """
  @callback compute_checksum(term()) :: binary()

  @optional_callbacks [compute_checksum: 1]
end
