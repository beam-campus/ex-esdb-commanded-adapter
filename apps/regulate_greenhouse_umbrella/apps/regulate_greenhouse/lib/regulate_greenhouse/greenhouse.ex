defmodule RegulateGreenhouse.Greenhouse do
  @moduledoc """
  Greenhouse aggregate for event sourcing.
  
  This aggregate handles commands related to greenhouse regulation
  and maintains the current state of a greenhouse.
  """

  alias RegulateGreenhouse.Commands.{
    CreateGreenhouse,
    SetTemperature,
    SetHumidity,
    SetLight,
    MeasureTemperature,
    MeasureHumidity,
    MeasureLight
  }

  alias RegulateGreenhouse.Events.{
    GreenhouseCreated,
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

  def execute(%__MODULE__{greenhouse_id: nil}, %CreateGreenhouse{} = command) do
    require Logger
    Logger.info("Greenhouse.execute: Creating greenhouse #{command.greenhouse_id}")
    
    event = %GreenhouseCreated{
      greenhouse_id: command.greenhouse_id,
      name: command.name,
      location: command.location,
      target_temperature: command.target_temperature,
      target_humidity: command.target_humidity,
      created_at: DateTime.utc_now()
    }
    
    Logger.info("Greenhouse.execute: Produced GreenhouseCreated event for #{command.greenhouse_id}")
    event
  end

  def execute(%__MODULE__{greenhouse_id: greenhouse_id}, %CreateGreenhouse{greenhouse_id: greenhouse_id}) do
    {:error, :greenhouse_already_exists}
  end

  def execute(%__MODULE__{greenhouse_id: nil}, _command) do
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
    %LightSet{
      greenhouse_id: command.greenhouse_id,
      target_light: command.target_light,
      previous_light: greenhouse.target_light,
      set_by: command.set_by,
      set_at: DateTime.utc_now()
    }
  end

  def execute(%__MODULE__{} = greenhouse, %MeasureTemperature{greenhouse_id: greenhouse_id} = command)
      when is_binary(greenhouse_id) do
    require Logger
    Logger.info("Greenhouse.execute: MeasureTemperature for #{greenhouse_id}, greenhouse state: #{inspect(greenhouse.greenhouse_id)}")
    
    %TemperatureMeasured{
      greenhouse_id: command.greenhouse_id,
      temperature: command.temperature,
      measured_at: command.measured_at
    }
  end

  def execute(%__MODULE__{} = greenhouse, %MeasureHumidity{greenhouse_id: greenhouse_id} = command)
      when is_binary(greenhouse_id) do
    require Logger
    Logger.info("Greenhouse.execute: MeasureHumidity for #{greenhouse_id}, greenhouse state: #{inspect(greenhouse.greenhouse_id)}")
    
    %HumidityMeasured{
      greenhouse_id: command.greenhouse_id,
      humidity: command.humidity,
      measured_at: command.measured_at
    }
  end

  def execute(%__MODULE__{} = greenhouse, %MeasureLight{greenhouse_id: greenhouse_id} = command)
      when is_binary(greenhouse_id) do
    require Logger
    Logger.info("Greenhouse.execute: MeasureLight for #{greenhouse_id}, greenhouse state: #{inspect(greenhouse.greenhouse_id)}")
    
    %LightMeasured{
      greenhouse_id: command.greenhouse_id,
      light: command.light,
      measured_at: command.measured_at
    }
  end

  def execute(%__MODULE__{}, _command) do
    {:error, :greenhouse_id_mismatch}
  end

  # State Mutators

  def apply(%__MODULE__{} = _greenhouse, %GreenhouseCreated{} = event) do
    %__MODULE__{
      greenhouse_id: event.greenhouse_id,
      name: event.name,
      location: event.location,
      target_temperature: event.target_temperature,
      target_humidity: event.target_humidity,
      created_at: event.created_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %TemperatureSet{} = event) do
    %__MODULE__{greenhouse | 
      target_temperature: event.target_temperature,
      updated_at: event.set_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %HumiditySet{} = event) do
    %__MODULE__{greenhouse | 
      target_humidity: event.target_humidity,
      updated_at: event.set_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %LightSet{} = event) do
    %__MODULE__{greenhouse | 
      target_light: event.target_light,
      updated_at: event.set_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %TemperatureMeasured{} = event) do
    %__MODULE__{greenhouse | 
      current_temperature: event.temperature,
      updated_at: event.measured_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %HumidityMeasured{} = event) do
    %__MODULE__{greenhouse | 
      current_humidity: event.humidity,
      updated_at: event.measured_at
    }
  end

  def apply(%__MODULE__{} = greenhouse, %LightMeasured{} = event) do
    %__MODULE__{greenhouse | 
      current_light: event.light,
      updated_at: event.measured_at
    }
  end
end
