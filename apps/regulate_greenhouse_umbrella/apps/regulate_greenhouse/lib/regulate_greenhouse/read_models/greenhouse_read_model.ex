defmodule RegulateGreenhouse.ReadModels.GreenhouseReadModel do
  @moduledoc """
  Read model for greenhouse projections.
  
  This struct represents the current state of a greenhouse
  as maintained by projections for fast querying.
  """

  @derive {Jason.Encoder, only: [
    :greenhouse_id, :name, :location, 
    :current_temperature, :current_humidity, :current_light,
    :target_temperature, :target_humidity, :target_light,
    :status, :event_count, :created_at, :updated_at
  ]}

  defstruct [
    :greenhouse_id,
    :name,
    :location,
    :current_temperature,
    :current_humidity, 
    :current_light,
    :target_temperature,
    :target_humidity,
    :target_light,
    :status,
    :event_count,
    :created_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
    greenhouse_id: String.t(),
    name: String.t(),
    location: String.t(),
    current_temperature: float() | nil,
    current_humidity: float() | nil,
    current_light: float() | nil,
    target_temperature: float() | nil,
    target_humidity: float() | nil,
    target_light: float() | nil,
    status: atom(),
    event_count: integer(),
    created_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  @doc """
  Determines the status of a greenhouse based on its readings and targets.
  """
  def calculate_status(%__MODULE__{} = read_model) do
    cond do
      all_readings_zero?(read_model) ->
        :inactive

      needs_attention?(read_model) ->
        :warning

      true ->
        :active
    end
  end

  defp all_readings_zero?(%__MODULE__{current_temperature: temp, current_humidity: hum, current_light: light}) do
    (temp == 0 or is_nil(temp)) and (hum == 0 or is_nil(hum)) and (light == 0 or is_nil(light))
  end

  defp needs_attention?(%__MODULE__{} = read_model) do
    temp_diff = case {read_model.current_temperature, read_model.target_temperature} do
      {current, target} when is_number(current) and is_number(target) ->
        abs(current - target) > 5
      _ -> false
    end

    humidity_diff = case {read_model.current_humidity, read_model.target_humidity} do
      {current, target} when is_number(current) and is_number(target) ->
        abs(current - target) > 20
      _ -> false
    end

    light_diff = case {read_model.current_light, read_model.target_light} do
      {current, target} when is_number(current) and is_number(target) ->
        abs(current - target) > 30
      _ -> false
    end

    temp_diff or humidity_diff or light_diff
  end
end
