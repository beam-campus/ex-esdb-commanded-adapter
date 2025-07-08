defmodule RegulateGreenhouse.Events do
  @moduledoc """
  Events for greenhouse regulation domain.
  """

  defmodule GreenhouseInitialized do
    @moduledoc """
    Event raised when a greenhouse is created.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :name, :location]
    defstruct [
      :greenhouse_id,
      :name,
      :location,
      :target_temperature,
      :target_humidity,
      :created_at
    ]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            name: String.t(),
            location: String.t(),
            target_temperature: float() | nil,
            target_humidity: float() | nil,
            created_at: DateTime.t()
          }
  end

  defmodule TemperatureSet do
    @moduledoc """
    Event raised when target temperature is set for a greenhouse.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :target_temperature]
    defstruct [:greenhouse_id, :target_temperature, :previous_temperature, :set_by, :set_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            target_temperature: float(),
            previous_temperature: float() | nil,
            set_by: String.t() | nil,
            set_at: DateTime.t()
          }
  end

  defmodule HumiditySet do
    @moduledoc """
    Event raised when target humidity is set for a greenhouse.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :target_humidity]
    defstruct [:greenhouse_id, :target_humidity, :previous_humidity, :set_by, :set_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            target_humidity: float(),
            previous_humidity: float() | nil,
            set_by: String.t() | nil,
            set_at: DateTime.t()
          }
  end

  defmodule LightSet do
    @moduledoc """
    Event raised when target light level is set for a greenhouse.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :target_light]
    defstruct [:greenhouse_id, :target_light, :previous_light, :set_by, :set_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            target_light: float(),
            previous_light: float() | nil,
            set_by: String.t() | nil,
            set_at: DateTime.t()
          }
  end

  defmodule TemperatureMeasured do
    @moduledoc """
    Event raised when temperature is measured in a greenhouse.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :temperature, :measured_at]
    defstruct [:greenhouse_id, :temperature, :measured_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            temperature: float(),
            measured_at: DateTime.t()
          }
  end

  defmodule HumidityMeasured do
    @moduledoc """
    Event raised when humidity is measured in a greenhouse.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :humidity, :measured_at]
    defstruct [:greenhouse_id, :humidity, :measured_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            humidity: float(),
            measured_at: DateTime.t()
          }
  end

  defmodule LightMeasured do
    @moduledoc """
    Event raised when light is measured in a greenhouse.
    """

    @derive Jason.Encoder
    @enforce_keys [:greenhouse_id, :light, :measured_at]
    defstruct [:greenhouse_id, :light, :measured_at]

    @type t :: %__MODULE__{
            greenhouse_id: String.t(),
            light: float(),
            measured_at: DateTime.t()
          }
  end
end
