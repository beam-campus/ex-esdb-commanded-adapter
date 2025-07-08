defmodule RegulateGreenhouse.Router do
  @moduledoc """
  Command router for RegulateGreenhouse.

  This router defines how commands are dispatched to aggregates
  in the greenhouse regulation domain.
  """

  use Commanded.Commands.Router

  middleware(RegulateGreenhouse.Middleware.LoggingMiddleware)

  alias RegulateGreenhouse.Greenhouse

  alias RegulateGreenhouse.Commands.{
    InitializeGreenhouse,
    SetTemperature,
    SetHumidity,
    SetLight,
    MeasureTemperature,
    MeasureHumidity,
    MeasureLight
  }

  # Route commands to the Greenhouse aggregate
  identify(Greenhouse, by: :greenhouse_id)

  dispatch(
    [
      InitializeGreenhouse,
      SetTemperature,
      SetHumidity,
      SetLight,
      MeasureTemperature,
      MeasureHumidity,
      MeasureLight
    ],
    to: Greenhouse
  )
end
