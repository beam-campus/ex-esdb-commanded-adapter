defmodule ExESDB.Commanded.ProjectionsRebuilder do
  @moduledoc """
  Generic projection rebuilder for ExESDB Commanded applications.

  Provides facilities for:
  - Rebuilding specific projections
  - Rebuilding all projections
  - Tracking rebuild progress
  - Handling rebuild failures
  - Supporting concurrent rebuilds
  """

  use GenServer
  require Logger

  # Types
  @type rebuild_status :: :not_started | :in_progress | :completed | :failed
  @type projection_info :: %{
    name: module(),
    status: rebuild_status(),
    started_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil,
    error: any()
  }

  @type rebuild_opts :: [
    application: module(),          # The Commanded application
    timeout: non_neg_integer(),     # Rebuild timeout in milliseconds
    batch_size: pos_integer(),      # Number of events to process in each batch
    concurrency: pos_integer()      # Number of concurrent projection rebuilds
  ]

  # Client API

  @doc """
  Starts the rebuilder for a specific Commanded application.
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Rebuilds specific projections.

  Options:
  - :timeout - Maximum time to wait for rebuild (default: 30_000ms)
  - :batch_size - Events to process in each batch (default: 1000)
  - :concurrency - Number of concurrent rebuilds (default: 1)
  """
  @spec rebuild_projections([module()], rebuild_opts()) :: 
    {:ok, [projection_info()]} | {:error, term()}
  def rebuild_projections(projections, opts \\ []) when is_list(projections) do
    GenServer.call(rebuilder_name(opts), {:rebuild, projections, opts}, opts[:timeout] || 30_000)
  end

  @doc """
  Rebuilds all projections for the configured Commanded application.
  """
  @spec rebuild_all(rebuild_opts()) :: {:ok, [projection_info()]} | {:error, term()}
  def rebuild_all(opts \\ []) do
    case discover_projections(opts[:application]) do
      {:ok, projections} -> rebuild_projections(projections, opts)
      error -> error
    end
  end

  @doc """
  Gets the current status of projection rebuilds.
  """
  @spec status(keyword()) :: %{projections: [projection_info()]}
  def status(opts \\ []) do
    GenServer.call(rebuilder_name(opts), :status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      application: Keyword.fetch!(opts, :application),
      projections: %{},
      in_progress: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:rebuild, projections, opts}, _from, state) do
    # Validate projections
    with :ok <- validate_projections(projections, state.application) do
      # Start rebuild process
      result = do_rebuild(projections, opts, state)
      {:reply, result, update_state(state, result)}
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{projections: Map.values(state.projections)}, state}
  end

  # Private Functions

  defp do_rebuild(projections, opts, state) do
    # 1. Stop existing projections
    stop_results = Enum.map(projections, &stop_projection(&1, state.application))

    # 2. Reset event handlers
    reset_results = Enum.map(projections, &reset_projection(&1, state.application))

    # 3. Configure rebuild options
    rebuild_opts = %{
      batch_size: opts[:batch_size] || 1000,
      concurrency: opts[:concurrency] || 1
    }

    # 4. Start rebuilds (potentially in parallel based on concurrency)
    case {stop_results, reset_results} do
      {stops, resets} when stops == [:ok] and resets == [:ok] ->
        projections
        |> Task.async_stream(
          &rebuild_projection(&1, state.application, rebuild_opts),
          max_concurrency: rebuild_opts.concurrency,
          timeout: opts[:timeout] || 30_000
        )
        |> Enum.reduce_while(
          {:ok, []},
          fn
            {:ok, {:ok, info}}, {:ok, infos} -> {:cont, {:ok, [info | infos]}}
            {:ok, {:error, reason}}, _ -> {:halt, {:error, reason}}
            {:exit, reason}, _ -> {:halt, {:error, {:rebuild_failed, reason}}}
          end
        )

      _ ->
        {:error, :preparation_failed}
    end
  end

  defp rebuild_projection(projection, application, opts) do
    Logger.info("Starting rebuild of projection: #{inspect(projection)}")
    start_time = DateTime.utc_now()

    try do
      # Start the projection (will trigger event replay)
      case application.start_event_handler(projection, opts) do
        {:ok, _pid} ->
          info = %{
            name: projection,
            status: :completed,
            started_at: start_time,
            completed_at: DateTime.utc_now(),
            error: nil
          }
          {:ok, info}

        {:error, reason} ->
          info = %{
            name: projection,
            status: :failed,
            started_at: start_time,
            completed_at: DateTime.utc_now(),
            error: reason
          }
          {:error, info}
      end
    catch
      kind, reason ->
        Logger.error("Projection rebuild failed: #{inspect({kind, reason})}")
        {:error, {kind, reason, __STACKTRACE__}}
    end
  end

  defp stop_projection(projection, application) do
    case application.stop_event_handler(projection) do
      :ok -> :ok
      {:error, :not_found} -> :ok  # Already stopped
      error -> error
    end
  end

  defp reset_projection(projection, application) do
    case application.reset_event_handler(projection) do
      :ok -> :ok
      {:error, :not_found} -> :ok  # Not yet started
      error -> error
    end
  end

  defp validate_projections(projections, application) do
    invalid =
      projections
      |> Enum.reject(&projection_valid?(&1, application))
      |> Enum.map(&to_string/1)

    if invalid == [] do
      :ok
    else
      {:error, {:invalid_projections, invalid}}
    end
  end

  defp projection_valid?(projection, application) do
    Code.ensure_loaded?(projection) &&
      function_exported?(projection, :init, 0) &&
      function_exported?(projection, :handle, 2) &&
      projection_uses_application?(projection, application)
  end

  defp projection_uses_application?(projection, application) do
    # Check if projection is configured to use this application
    # This might need adaptation based on how projections are configured
    true
  end

  defp discover_projections(application) do
    # Discover all projections in the application
    # This could be done through configuration or module attributes
    {:ok, []}
  end

  defp rebuilder_name(opts) do
    opts[:name] || __MODULE__
  end

  defp update_state(state, {:ok, infos}) do
    new_projections =
      Enum.reduce(infos, state.projections, fn info, acc ->
        Map.put(acc, info.name, info)
      end)

    %{state | projections: new_projections}
  end

  defp update_state(state, _error), do: state
end
