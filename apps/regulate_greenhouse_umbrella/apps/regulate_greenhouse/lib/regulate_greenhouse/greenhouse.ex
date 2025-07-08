defmodule RegulateGreenhouse.Greenhouse do
  @moduledoc """
  Greenhouse aggregate for event sourcing.

  This aggregate handles commands related to greenhouse regulation
  and maintains the current state of a greenhouse.
  """

  alias RegulateGreenhouse.Commands.{
    InitializeGreenhouse,
    SetTemperature,
    SetHumidity,
    SetLight,
    MeasureTemperature,
    MeasureHumidity,
    MeasureLight
  }

  alias RegulateGreenhouse.Events.{
    GreenhouseInitialized,
    TemperatureSet,
    HumiditySet,
    LightSet,
    TemperatureMeasured,
    HumidityMeasured,
    LightMeasured
  }

  @type t :: %__MODULE__{
          greenhouse_id: String.t() | nil,
          name: String.t() | nil,
          location: String.t() | nil,
          target_temperature: float() | nil,
          target_humidity: float() | nil,
          target_light: float() | nil,
          current_temperature: float() | nil,
          current_humidity: float() | nil,
          current_light: float() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :greenhouse_id,
    :name,
    :location,
    :target_temperature,
    :target_humidity,
    :target_light,
    :current_temperature,
    :current_humidity,
    :current_light,
    :created_at,
    :updated_at
  ]

  # Command Handlers

  def execute(%__MODULE__{greenhouse_id: nil}, %InitializeGreenhouse{} = command) do
    require Logger
    Logger.info("Greenhouse.execute: Creating greenhouse #{command.greenhouse_id}")

    event = %GreenhouseInitialized{
      greenhouse_id: command.greenhouse_id,
      name: command.name,
      location: command.location,
      target_temperature: command.target_temperature,
      target_humidity: command.target_humidity,
      created_at: DateTime.utc_now()
    }

    Logger.info(
      "Greenhouse.execute: Produced GreenhouseInitialized event for #{command.greenhouse_id}"
    )

    event
  end

  def execute(%__MODULE__{greenhouse_id: greenhouse_id}, %InitializeGreenhouse{
        greenhouse_id: greenhouse_id
      }) do
    {:error, :greenhouse_already_exists}
  end

  def execute(%__MODULE__{greenhouse_id: nil} = state, command) do
    require Logger
    Logger.error("Greenhouse.execute: greenhouse_not_found - state has nil greenhouse_id")
    Logger.error("Greenhouse.execute: State: #{inspect(state)}")
    Logger.error("Greenhouse.execute: Command: #{inspect(command)}")
    {:error, :greenhouse_not_found}
  end

  def execute(%__MODULE__{} = greenhouse, %SetTemperature{greenhouse_id: greenhouse_id} = command)
      when greenhouse.greenhouse_id == greenhouse_id do
    %TemperatureSet{
      greenhouse_id: command.greenhouse_id,
      target_temperature: command.target_temperature,
      previous_temperature: greenhouse.target_temperature,
      set_by: command.set_by,
      set_at: DateTime.utc_now()
    }
  end

  def execute(%__MODULE__{} = greenhouse, %SetHumidity{greenhouse_id: greenhouse_id} = command)
      when greenhouse.greenhouse_id == greenhouse_id do
    %HumiditySet{
      greenhouse_id: command.greenhouse_id,
      target_humidity: command.target_humidity,
      previous_humidity: greenhouse.target_humidity,
      set_by: command.set_by,
      set_at: DateTime.utc_now()
    }
  end

  def execute(%__MODULE__{} = greenhouse, %SetLight{greenhouse_id: greenhouse_id} = command)
      when greenhouse.greenhouse_id == greenhouse_id do
    require Logger

    Logger.info(
      "Greenhouse.execute: SetLight for #{greenhouse_id}, state greenhouse_id: #{greenhouse.greenhouse_id}"
    )

    %LightSet{
      greenhouse_id: command.greenhouse_id,
      target_light: command.target_light,
      previous_light: greenhouse.target_light,
      set_by: command.set_by,
      set_at: DateTime.utc_now()
    }
  end

  def execute(
        %__MODULE__{} = greenhouse,
        %MeasureTemperature{greenhouse_id: greenhouse_id} = command
      )
      when greenhouse.greenhouse_id == greenhouse_id do
    require Logger

    Logger.info(
      "Greenhouse.execute: MeasureTemperature for #{greenhouse_id}, temperature: #{command.temperature}°C"
    )

    %TemperatureMeasured{
      greenhouse_id: command.greenhouse_id,
      temperature: command.temperature,
      measured_at: command.measured_at
    }
  end

  def execute(
        %__MODULE__{} = greenhouse,
        %MeasureHumidity{greenhouse_id: greenhouse_id} = command
      )
      when greenhouse.greenhouse_id == greenhouse_id do
    require Logger

    Logger.info(
      "Greenhouse.execute: MeasureHumidity for #{greenhouse_id}, humidity: #{command.humidity}%"
    )

    %HumidityMeasured{
      greenhouse_id: command.greenhouse_id,
      humidity: command.humidity,
      measured_at: command.measured_at
    }
  end

  def execute(%__MODULE__{} = greenhouse, %MeasureLight{greenhouse_id: greenhouse_id} = command)
      when greenhouse.greenhouse_id == greenhouse_id do
    require Logger

    Logger.info(
      "Greenhouse.execute: MeasureLight for #{greenhouse_id}, light: #{command.light} lumens"
    )

    %LightMeasured{
      greenhouse_id: command.greenhouse_id,
      light: command.light,
      measured_at: command.measured_at
    }
  end

  def execute(%__MODULE__{} = greenhouse, command) do
    require Logger
    command_name = command.__struct__ |> to_string() |> String.split(".") |> List.last()
    command_greenhouse_id = Map.get(command, :greenhouse_id, "unknown")

    Logger.error("Greenhouse.execute: Command #{command_name} failed - greenhouse_id mismatch")
    Logger.error("Greenhouse.execute: Command greenhouse_id: #{command_greenhouse_id}")
    Logger.error("Greenhouse.execute: State greenhouse_id: #{inspect(greenhouse.greenhouse_id)}")
    Logger.error("Greenhouse.execute: Full state: #{inspect(greenhouse)}")
    Logger.error("Greenhouse.execute: Full command: #{inspect(command)}")

    {:error, :greenhouse_id_mismatch}
  end

  # State Mutators

  def apply(%__MODULE__{} = _greenhouse, %GreenhouseInitialized{} = event) do
    require Logger
    Logger.info("Greenhouse.apply: GreenhouseInitialized event for #{event.greenhouse_id}")
    Logger.debug("Greenhouse.apply: Event data: #{inspect(event)}")

    new_state = %__MODULE__{
      greenhouse_id: event.greenhouse_id,
      name: event.name,
      location: event.location,
      target_temperature: event.target_temperature,
      target_humidity: event.target_humidity,
      created_at: event.created_at
    }

    Logger.info("Greenhouse.apply: New state greenhouse_id: #{new_state.greenhouse_id}")
    new_state
  end

  def apply(%__MODULE__{} = greenhouse, %TemperatureSet{} = event) do
    require Logger

    Logger.info(
      "Greenhouse.apply: TemperatureSet for #{event.greenhouse_id}, target: #{event.target_temperature}°C"
    )

    %__MODULE__{
      greenhouse
      | target_temperature: event.target_temperature,
        updated_at: event.set_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %HumiditySet{} = event) do
    require Logger

    Logger.info(
      "Greenhouse.apply: HumiditySet for #{event.greenhouse_id}, target: #{event.target_humidity}%"
    )

    %__MODULE__{greenhouse | target_humidity: event.target_humidity, updated_at: event.set_at}
  end

  def apply(%__MODULE__{} = greenhouse, %LightSet{} = event) do
    require Logger

    Logger.info(
      "Greenhouse.apply: LightSet for #{event.greenhouse_id}, target: #{event.target_light} lumens"
    )

    %__MODULE__{greenhouse | target_light: event.target_light, updated_at: event.set_at}
  end

  def apply(%__MODULE__{} = greenhouse, %TemperatureMeasured{} = event) do
    require Logger

    Logger.info(
      "Greenhouse.apply: TemperatureMeasured for #{event.greenhouse_id}, temperature: #{event.temperature}°C"
    )

    %__MODULE__{
      greenhouse
      | current_temperature: event.temperature,
        updated_at: event.measured_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %HumidityMeasured{} = event) do
    require Logger

    Logger.info(
      "Greenhouse.apply: HumidityMeasured for #{event.greenhouse_id}, humidity: #{event.humidity}%"
    )

    %__MODULE__{greenhouse | current_humidity: event.humidity, updated_at: event.measured_at}
  end

  def apply(%__MODULE__{} = greenhouse, %LightMeasured{} = event) do
    require Logger

    Logger.info(
      "Greenhouse.apply: LightMeasured for #{event.greenhouse_id}, light: #{event.light} lumens"
    )

    %__MODULE__{greenhouse | current_light: event.light, updated_at: event.measured_at}
  end
end
