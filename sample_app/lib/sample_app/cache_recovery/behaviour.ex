defmodule SampleApp.CacheRecovery.Behaviour do
  @moduledoc """
  Behaviour defining the contract for cache recovery implementations.
  """

  @type cache_name :: atom()
  @type schema :: module()
  @type error :: {:error, term()}

  @doc """
  Recovers a specific cache from the database.
  The cache will be populated with all records from the corresponding database table.
  """
  @callback recover_cache(cache_name(), schema()) ::
    :ok | error()

  @doc """
  Recovers all registered caches from their respective database tables.
  """
  @callback recover_all_caches() ::
    :ok | error()

  @doc """
  Registers a cache for recovery, associating it with a database schema.
  """
  @callback register_cache(cache_name(), schema()) ::
    :ok | error()

  @doc """
  Unregisters a cache from recovery.
  """
  @callback unregister_cache(cache_name()) ::
    :ok | error()
end
