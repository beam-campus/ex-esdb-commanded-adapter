defmodule RegulateGreenhouse.Infrastructure.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for protecting event processing from overload.
  
  This module provides circuit breaker functionality to prevent cascading failures
  when event processing is under heavy load or experiencing errors.
  """
  
  use GenServer
  require Logger
  
  @type state :: :closed | :open | :half_open
  @type config :: %{
    failure_threshold: non_neg_integer(),
    recovery_timeout: non_neg_integer(),
    reset_timeout: non_neg_integer()
  }
  
  defstruct [
    :name,
    :config,
    :state,
    :failure_count,
    :last_failure_time,
    :next_attempt_time
  ]
  
  @default_config %{
    failure_threshold: 5,
    recovery_timeout: 60_000,  # 1 minute
    reset_timeout: 30_000      # 30 seconds
  }
  
  # Client API
  
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    config = Keyword.get(opts, :config, @default_config)
    
    GenServer.start_link(__MODULE__, {name, config}, name: name)
  end
  
  @doc """
  Execute a function with circuit breaker protection.
  """
  def call(circuit_breaker, fun) when is_function(fun, 0) do
    GenServer.call(circuit_breaker, {:call, fun})
  end
  
  @doc """
  Get current circuit breaker state.
  """
  def state(circuit_breaker) do
    GenServer.call(circuit_breaker, :state)
  end
  
  @doc """
  Reset circuit breaker to closed state.
  """
  def reset(circuit_breaker) do
    GenServer.call(circuit_breaker, :reset)
  end
  
  # Server Implementation
  
  @impl GenServer
  def init({name, config}) do
    state = %__MODULE__{
      name: name,
      config: Map.merge(@default_config, config),
      state: :closed,
      failure_count: 0,
      last_failure_time: nil,
      next_attempt_time: nil
    }
    
    Logger.info("CircuitBreaker #{name} initialized in :closed state")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:call, fun}, _from, %{state: :open} = state) do
    now = System.monotonic_time(:millisecond)
    
    if state.next_attempt_time && now >= state.next_attempt_time do
      # Transition to half-open and try the call
      new_state = %{state | state: :half_open}
      Logger.info("CircuitBreaker #{state.name} transitioning to :half_open")
      
      case execute_with_circuit_breaker(fun, new_state) do
        {:ok, result, updated_state} ->
          {:reply, {:ok, result}, updated_state}
        {:error, reason, updated_state} ->
          {:reply, {:error, {:circuit_breaker, reason}}, updated_state}
      end
    else
      Logger.debug("CircuitBreaker #{state.name} is :open, rejecting call")
      {:reply, {:error, :circuit_breaker_open}, state}
    end
  end
  
  def handle_call({:call, fun}, _from, state) do
    case execute_with_circuit_breaker(fun, state) do
      {:ok, result, updated_state} ->
        {:reply, {:ok, result}, updated_state}
      {:error, reason, updated_state} ->
        {:reply, {:error, {:circuit_breaker, reason}}, updated_state}
    end
  end
  
  def handle_call(:state, _from, state) do
    {:reply, 
     %{
       state: state.state,
       failure_count: state.failure_count,
       last_failure_time: state.last_failure_time
     }, 
     state}
  end
  
  def handle_call(:reset, _from, state) do
    Logger.info("CircuitBreaker #{state.name} manually reset to :closed")
    new_state = %{state | 
      state: :closed, 
      failure_count: 0, 
      last_failure_time: nil,
      next_attempt_time: nil
    }
    {:reply, :ok, new_state}
  end
  
  # Private Functions
  
  defp execute_with_circuit_breaker(fun, state) do
    try do
      result = fun.()
      handle_success(result, state)
    rescue
      error ->
        handle_failure(error, state)
    catch
      :exit, reason ->
        handle_failure({:exit, reason}, state)
      :throw, reason ->
        handle_failure({:throw, reason}, state)
    end
  end
  
  defp handle_success(result, %{state: circuit_state} = state) do
    case circuit_state do
      :half_open ->
        # Successful call in half-open state transitions back to closed
        Logger.info("CircuitBreaker #{state.name} transitioning to :closed after successful call")
        new_state = %{state | 
          state: :closed, 
          failure_count: 0,
          last_failure_time: nil,
          next_attempt_time: nil
        }
        {:ok, result, new_state}
      
      _ ->
        # Reset failure count on success
        new_state = %{state | failure_count: 0, last_failure_time: nil}
        {:ok, result, new_state}
    end
  end
  
  defp handle_failure(error, state) do
    now = System.monotonic_time(:millisecond)
    new_failure_count = state.failure_count + 1
    
    Logger.warning("CircuitBreaker #{state.name} failure ##{new_failure_count}: #{inspect(error)}")
    
    new_state = %{state | 
      failure_count: new_failure_count,
      last_failure_time: now
    }
    
    if new_failure_count >= state.config.failure_threshold do
      # Trip the circuit breaker
      next_attempt = now + state.config.recovery_timeout
      tripped_state = %{new_state | 
        state: :open,
        next_attempt_time: next_attempt
      }
      
      Logger.error("CircuitBreaker #{state.name} tripped! Entering :open state for #{state.config.recovery_timeout}ms")
      {:error, error, tripped_state}
    else
      {:error, error, new_state}
    end
  end
  
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
