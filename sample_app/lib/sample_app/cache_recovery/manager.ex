defmodule SampleApp.CacheRecovery.Manager do
  @moduledoc """
  Implementation of the cache recovery behaviour.
  Manages cache recovery from database tables.
  """
  @behaviour SampleApp.CacheRecovery.Behaviour

  use GenServer
  alias SampleApp.Repo
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, %{caches: %{}}}
  end

  @impl true
  def recover_cache(cache_name, schema) do
    GenServer.call(__MODULE__, {:recover_cache, cache_name, schema})
  end

  @impl true
  def recover_all_caches do
    GenServer.call(__MODULE__, :recover_all_caches)
  end

  @impl true
  def register_cache(cache_name, schema) do
    GenServer.call(__MODULE__, {:register_cache, cache_name, schema})
  end

  @impl true
  def unregister_cache(cache_name) do
    GenServer.call(__MODULE__, {:unregister_cache, cache_name})
  end

  # Server callbacks

  @impl true
  def handle_call({:recover_cache, cache_name, schema}, _from, state) do
    case do_recover_cache(cache_name, schema) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:recover_all_caches, _from, state) do
    results = Enum.map(state.caches, fn {cache_name, schema} ->
      {cache_name, do_recover_cache(cache_name, schema)}
    end)

    errors = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)

    case errors do
      [] -> {:reply, :ok, state}
      _ -> {:reply, {:error, errors}, state}
    end
  end

  @impl true
  def handle_call({:register_cache, cache_name, schema}, _from, state) do
    new_state = put_in(state.caches[cache_name], schema)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_cache, cache_name}, _from, state) do
    {_, new_caches} = Map.pop(state.caches, cache_name)
    {:reply, :ok, %{state | caches: new_caches}}
  end

  # Private functions

  defp do_recover_cache(cache_name, schema) do
    try do
      # Get all records from the database
      records = Repo.all(schema)

      # For each record, get its cache key and store in cache
      for record <- records do
        key = get_cache_key(record)
        :ok = Cachex.put!(cache_name, key, record)
      end

      Logger.info("✅ Recovered #{length(records)} records for cache: #{cache_name}")
      :ok
    rescue
      error ->
        Logger.error("⚠️ Failed to recover cache #{cache_name}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_cache_key(%{poll_id: poll_id}), do: poll_id
  defp get_cache_key(%{voter_id: voter_id}), do: voter_id
  defp get_cache_key(record), do: raise "No cache key found for record: #{inspect(record)}"
end
