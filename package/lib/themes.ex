defmodule ExESDB.Commanded.Themes do
  @moduledoc false
  alias BCUtils.ColorFuncs, as: CF

  def aggregate_listener(pid, msg),
    do:
      "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}][AGG LISTENER] #{CF.green_on_black()}#{inspect(msg)}#{CF.reset()}"

  def aggregate_listener_supervisor(pid, msg),
    do:
      "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}][AGG SUPERVISOR] #{CF.green_on_black()}#{inspect(msg)}#{CF.reset()}"
end
