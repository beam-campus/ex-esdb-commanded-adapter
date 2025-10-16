defmodule SampleApp.SnapshotCoordinator do
  @moduledoc false
  use GenServer
  alias ExESDB.StoreNaming

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  ###################### PLUMBING ######################
  def start_link(init_arg) do
    store = store(init_arg)
    name = StoreNaming.genserver_name(store, :snapshot_coordinator)

    GenServer.start_link(
      __MODULE__,
      init_arg,
      name: name
    )
  end

  defp store(init_arg), do: Keyword.get(init_arg, :store, :undefined)
end
