defmodule ExESDB.Commanded.Config do
  @moduledoc """
  Configuration validation and normalization for ExESDB.Commanded.Adapter.
  
  This module provides standardized configuration handling with proper validation,
  error handling, and normalization to ensure consistent behavior between Commanded
  and ExESDB systems.
  """

  require Logger

  @type config :: Keyword.t()
  @type adapter_config :: map()

  @doc """
  Validates and normalizes configuration for ExESDB.Commanded.Adapter.
  
  ## Options
  
  * `:store_id` - ExESDB store identifier (required)
  * `:stream_prefix` - Prefix for all streams (default: "")
  * `:serializer` - Serialization module (default: Jason)
  * `:use_libcluster` - Whether to use libcluster for node discovery (default: true)
  * `:connection_timeout` - Connection timeout in ms (default: 10_000)
  * `:retry_attempts` - Number of retry attempts for failed operations (default: 3)
  * `:retry_backoff` - Backoff interval between retries in ms (default: 1_000)
  
  ## Examples
  
      iex> ExESDB.Commanded.Config.validate([store_id: :my_store])
      {:ok, %{store_id: :my_store, stream_prefix: "", ...}}
      
      iex> ExESDB.Commanded.Config.validate([])
      {:error, {:missing_required_config, [:store_id]}}
  """
  @spec validate(config()) :: {:ok, adapter_config()} | {:error, {atom(), term()}}
  def validate(config) when is_list(config) do
    with {:ok, validated_config} <- validate_required_fields(config),
         {:ok, normalized_config} <- normalize_config(validated_config) do
      {:ok, normalized_config}
    end
  rescue
    error -> {:error, {:validation_error, error}}
  end

  @doc """
  Gets the store ID from configuration or environment.
  """
  @spec store_id(config()) :: atom()
  def store_id(config) do
    case get_config_value(config, :store_id, "EXESDB_COMMANDED_STORE_ID") do
      nil -> raise ArgumentError, "store_id is required"
      value when is_binary(value) -> String.to_atom(value)
      value when is_atom(value) -> value
    end
  end

  @doc """
  Gets the stream prefix from configuration or environment.
  
  Stream prefixes cannot contain dashes to avoid conflicts with ExESDB
  internal naming conventions.
  """
  @spec stream_prefix(config()) :: String.t()
  def stream_prefix(config) do
    case get_config_value(config, :stream_prefix, "EXESDB_COMMANDED_STREAM_PREFIX") do
      nil -> ""
      value when is_binary(value) -> validate_stream_prefix(value)
    end
  end

  @doc """
  Gets the serializer module from configuration or environment.
  """
  @spec serializer(config()) :: module()
  def serializer(config) do
    case get_config_value(config, :serializer, "EXESDB_COMMANDED_SERIALIZER") do
      nil -> Jason
      value when is_atom(value) -> value
      value when is_binary(value) -> String.to_existing_atom(value)
    end
  end

  @doc """
  Checks if libcluster should be used for node discovery.
  """
  @spec use_libcluster?(config()) :: boolean()
  def use_libcluster?(config) do
    case get_config_value(config, :use_libcluster, "EXESDB_COMMANDED_USE_LIBCLUSTER") do
      nil -> true
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      other -> raise ArgumentError, "use_libcluster must be a boolean, got: #{inspect(other)}"
    end
  end

  @doc """
  Gets the connection timeout from configuration or environment.
  """
  @spec connection_timeout(config()) :: pos_integer()
  def connection_timeout(config) do
    case get_config_value(config, :connection_timeout, "EXESDB_COMMANDED_CONNECTION_TIMEOUT") do
      nil -> 10_000
      value when is_integer(value) and value > 0 -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_val, ""} when int_val > 0 -> int_val
          _ -> raise ArgumentError, "connection_timeout must be a positive integer"
        end
    end
  end

  @doc """
  Gets the retry attempts from configuration or environment.
  """
  @spec retry_attempts(config()) :: non_neg_integer()
  def retry_attempts(config) do
    case get_config_value(config, :retry_attempts, "EXESDB_COMMANDED_RETRY_ATTEMPTS") do
      nil -> 3
      value when is_integer(value) and value >= 0 -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_val, ""} when int_val >= 0 -> int_val
          _ -> raise ArgumentError, "retry_attempts must be a non-negative integer"
        end
    end
  end

  @doc """
  Gets the retry backoff from configuration or environment.
  """
  @spec retry_backoff(config()) :: pos_integer()
  def retry_backoff(config) do
    case get_config_value(config, :retry_backoff, "EXESDB_COMMANDED_RETRY_BACKOFF") do
      nil -> 1_000
      value when is_integer(value) and value > 0 -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_val, ""} when int_val > 0 -> int_val
          _ -> raise ArgumentError, "retry_backoff must be a positive integer"
        end
    end
  end

  @doc """
  Validates that the serializer module is available and has required functions.
  """
  @spec validate_serializer(module()) :: {:ok, module()} | {:error, term()}
  def validate_serializer(serializer) when is_atom(serializer) do
    try do
      Code.ensure_loaded!(serializer)
      
      # Check if module has required functions
      if function_exported?(serializer, :encode!, 1) and 
         function_exported?(serializer, :decode!, 1) do
        {:ok, serializer}
      else
        {:error, {:invalid_serializer, "serializer must export encode!/1 and decode!/1"}}
      end
    rescue
      _ -> {:error, {:invalid_serializer, "serializer module not available: #{serializer}"}}
    end
  end

  @doc """
  Validates libcluster topology configuration.
  """
  @spec validate_libcluster_config(config()) :: {:ok, config()} | {:error, term()}
  def validate_libcluster_config(config) do
    if use_libcluster?(config) do
      case Application.get_env(:libcluster, :topologies) do
        nil -> 
          Logger.warning("libcluster is enabled but no topologies configured")
          {:ok, config}
        topologies when is_list(topologies) ->
          Logger.info("libcluster enabled with #{length(topologies)} topologies")
          {:ok, config}
        invalid ->
          {:error, {:invalid_libcluster_config, invalid}}
      end
    else
      {:ok, config}
    end
  end

  # Private functions

  defp validate_required_fields(config) do
    required = [:store_id]
    missing = Enum.filter(required, fn key ->
      case get_config_value(config, key, nil) do
        nil -> true
        "" -> true
        _ -> false
      end
    end)

    case missing do
      [] -> {:ok, config}
      missing_keys -> {:error, {:missing_required_config, missing_keys}}
    end
  end

  defp normalize_config(config) do
    serializer_module = serializer(config)
    
    with {:ok, validated_serializer} <- validate_serializer(serializer_module),
         {:ok, _} <- validate_libcluster_config(config) do
      
      normalized = %{
        store_id: store_id(config),
        stream_prefix: stream_prefix(config),
        serializer: validated_serializer,
        use_libcluster: use_libcluster?(config),
        connection_timeout: connection_timeout(config),
        retry_attempts: retry_attempts(config),
        retry_backoff: retry_backoff(config)
      }
      
      {:ok, normalized}
    end
  end

  defp get_config_value(config, key, env_var) do
    case Keyword.get(config, key) do
      nil when is_binary(env_var) -> System.get_env(env_var)
      nil -> nil
      value -> value
    end
  end

  defp validate_stream_prefix(prefix) when is_binary(prefix) do
    case String.contains?(prefix, "-") do
      true -> raise ArgumentError, "stream_prefix cannot contain a dash (\"-\")"
      false -> prefix
    end
  end
end
