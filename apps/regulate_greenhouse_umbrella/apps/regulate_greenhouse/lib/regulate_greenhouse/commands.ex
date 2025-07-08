defmodule RegulateGreenhouse.Commands do
  @moduledoc """
  Commands for greenhouse regulation domain.
  """

  defmodule InitializeGreenhouse do
    @moduledoc """
    Command to initialize a new greenhouse.
    """

    @enforce_keys [:greenhouse_id, :name, :location]
    defstruct [:greenhouse_id, :name, :location, :target_temperature, :target_humidity]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            name: String.t(),
            location: String.t(),
            target_temperature: float() | nil,
            target_humidity: float() | nil
          }
  end

  defmodule SetTemperature do
    @moduledoc """
    Command to set target temperature for a greenhouse.
    """

    @enforce_keys [:greenhouse_id, :target_temperature]
    defstruct [:greenhouse_id, :target_temperature, :set_by]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            target_temperature: float(),
            set_by: String.t() | nil
          }
  end

  defmodule SetHumidity do
    @moduledoc """
    Command to set target humidity for a greenhouse.
    """

    @enforce_keys [:greenhouse_id, :target_humidity]
    defstruct [:greenhouse_id, :target_humidity, :set_by]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            target_humidity: float(),
            set_by: String.t() | nil
          }
  end

  defmodule SetLight do
    @moduledoc """
    Command to set target light level for a greenhouse.
    """

    @enforce_keys [:greenhouse_id, :target_light]
    defstruct [:greenhouse_id, :target_light, :set_by]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            target_light: float(),
            set_by: String.t() | nil
          }
  end

  defmodule MeasureTemperature do
    @moduledoc """
    Command to record a temperature measurement.
    """

    @enforce_keys [:greenhouse_id, :temperature, :measured_at]
    defstruct [:greenhouse_id, :temperature, :measured_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            temperature: float(),
            measured_at: DateTime.t()
          }
  end

  defmodule MeasureHumidity do
    @moduledoc """
    Command to record a humidity measurement.
    """

    @enforce_keys [:greenhouse_id, :humidity, :measured_at]
    defstruct [:greenhouse_id, :humidity, :measured_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            humidity: float(),
            measured_at: DateTime.t()
          }
  end

  defmodule MeasureLight do
    @moduledoc """
    Command to record a light measurement.
    """

    @enforce_keys [:greenhouse_id, :light, :measured_at]
    defstruct [:greenhouse_id, :light, :measured_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            light: float(),
            measured_at: DateTime.t()
          }
  end
end
