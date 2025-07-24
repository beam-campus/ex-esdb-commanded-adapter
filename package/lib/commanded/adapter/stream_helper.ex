defmodule ExESDB.Commanded.Adapter.StreamHelper do
  @moduledoc """
  Helper functions for stream operations and subscription type detection.
  """

  @doc """
  Determines if a stream subscription should be allowed based on the stream type.
  Allows:
  - $all streams (global) - aggregates should subscribe to this and filter by stream_id
  - Event type streams ($et-*) - for projection systems

  Blocks:
  - Individual stream subscriptions to prevent creating separate emitters per aggregate
  """
  def allowed_stream?(stream) do
    case stream do
      :all -> true
      "$all" -> true
      "$et-" <> _event_type -> true
      # Block all individual stream subscriptions to force use of $all
      # This prevents spinning up separate emitters for each aggregate instance
      _individual_stream -> false
    end
  end

  @doc """
  Converts a stream identifier to subscription type and selector.
  """
  def stream_to_subscription_params(stream, prefix \\ "") do
    case stream do
      :all -> {:by_stream, "$all"}
      "$all" -> {:by_stream, "$all"}
      "$et-" <> event_type -> {:by_event_type, event_type}
      stream_id when is_binary(stream_id) -> {:by_stream, "$#{prefix}#{stream_id}"}
    end
  end

  @doc """
  Converts start_from parameter to version number for ExESDB.
  """
  def normalize_start_version(start_from) do
    case start_from do
      :origin -> 0
      :current -> -1
      version when is_integer(version) -> version
    end
  end

  @doc """
  Normalizes Commanded expected versions to ExESDB expected versions.
  """
  def normalize_expected_version(:no_stream), do: -1
  def normalize_expected_version(:any_version), do: :any
  def normalize_expected_version(:stream_exists), do: :stream_exists

  def normalize_expected_version(version) when is_integer(version) and version >= 0,
    do: version - 1

  @doc """
  Maps ExESDB error responses to Commanded error format.
  """
  def map_error({:wrong_expected_version, actual_version}) do
    require Logger
    Logger.error("ADAPTER: Wrong expected version, actual version is: #{actual_version}")
    {:error, :wrong_expected_version}
  end

  def map_error({:error, {:wrong_expected_version, actual_version}}),
    do: map_error({:wrong_expected_version, actual_version})

  def map_error(:stream_not_found), do: {:error, :stream_not_found}
  def map_error(error), do: {:error, error}

  @doc """
  Extracts store configuration from adapter metadata.
  """
  def store_id(meta), do: Map.get(meta, :store_id, :ex_esdb)

  @doc """
  Extracts stream prefix from adapter metadata.
  """
  def stream_prefix(meta), do: Map.get(meta, :stream_prefix, "")

  def pubsub(meta) do
    IO.puts(" >>>>>>>>>>>>>>>>>>META: #{inspect(meta)} <<<<<<<<<<<<<<<<<<<<<<<<<<<")

    meta
    |> Map.get(:pubsub, %{})
  end

  def phoenix_pubsub(meta),
    do:
      meta
      |> pubsub()
      |> Map.get(:phoenix_pubsub, %{})

  def pubsub_name(meta, default),
    do:
      meta
      |> phoenix_pubsub()
      |> Map.get(:name, default)
end
