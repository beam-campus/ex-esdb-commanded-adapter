defmodule RegulateGreenhouseWeb.DashboardLive do
  use RegulateGreenhouseWeb, :live_view

  alias RegulateGreenhouse.API

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time greenhouse updates
      Phoenix.PubSub.subscribe(RegulateGreenhouse.PubSub, "greenhouse_updates")
      # Refresh data every 5 seconds as fallback
      :timer.send_interval(5000, self(), :refresh)
    end

    socket =
      socket
      |> assign(:greenhouses, load_greenhouses())
      |> assign(:page_title, "Greenhouse Dashboard")

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :greenhouses, load_greenhouses())}
  end

  @impl true
  def handle_info({:greenhouse_created, _read_model}, socket) do
    {:noreply, assign(socket, :greenhouses, load_greenhouses())}
  end

  @impl true
  def handle_info({:greenhouse_updated, _read_model, _event_type}, socket) do
    {:noreply, assign(socket, :greenhouses, load_greenhouses())}
  end

  @impl true
  def handle_event("initialize_greenhouse", %{"greenhouse_id" => greenhouse_id}, socket) do
    require Logger
    Logger.info("Dashboard: Initializing greenhouse #{greenhouse_id}")

    # Generate initial sensor readings
    temperature = 20 + :rand.uniform(10)
    humidity = 40 + :rand.uniform(30)
    light = 30 + :rand.uniform(40)

    Logger.info("Dashboard: Generated readings - T:#{temperature}, H:#{humidity}, L:#{light}")

    case API.initialize_greenhouse(greenhouse_id, temperature, humidity, light) do
      :ok ->
        Logger.info(
          "Dashboard: Greenhouse #{greenhouse_id} initialized successfully, reloading data"
        )

        new_greenhouses = load_greenhouses()
        Logger.info("Dashboard: Pushing close-modal event and updating UI")

        socket =
          socket
          |> put_flash(:info, "Greenhouse #{greenhouse_id} initialized successfully!")
          |> assign(:greenhouses, new_greenhouses)
          |> push_event("close-modal", %{id: "new-greenhouse-modal"})

        {:noreply, socket}

      {:error, reason} ->
        Logger.error(
          "Dashboard: Failed to initialize greenhouse #{greenhouse_id}: #{inspect(reason)}"
        )

        socket = put_flash(socket, :error, "Failed to initialize greenhouse: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <.icon name="hero-home" class="h-8 w-8 text-green-600 mr-3" />
              <h1 class="text-2xl font-bold text-gray-900">Greenhouse Control Center</h1>
            </div>
            <div class="flex items-center space-x-4">
              <.button
                phx-click={show_modal("new-greenhouse-modal")}
                class="bg-green-600 hover:bg-green-700 text-white"
              >
                <.icon name="hero-plus" class="h-4 w-4 mr-2" /> Initialize New Greenhouse
              </.button>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Stats Overview -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-home-modern" class="h-6 w-6 text-gray-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Total Greenhouses</dt>
                    <dd class="text-lg font-medium text-gray-900">{length(@greenhouses)}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Active</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {@greenhouses |> Enum.count(&(&1.status == :active))}
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-exclamation-triangle" class="h-6 w-6 text-yellow-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Needs Attention</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {@greenhouses |> Enum.count(&(&1.status == :warning))}
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-thermometer" class="h-6 w-6 text-blue-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Avg. Temperature</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {calculate_avg_temperature(@greenhouses)}°C
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Greenhouses Grid -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <%= for greenhouse <- @greenhouses do %>
            <.link navigate={~p"/greenhouse/#{greenhouse.id}"} class="block">
              <div class="bg-white overflow-hidden shadow-lg rounded-xl hover:shadow-xl transition-all duration-300 transform hover:-translate-y-1 cursor-pointer border-2 border-transparent hover:border-green-500 hover:ring-2 hover:ring-green-200 hover:ring-opacity-50">
              <!-- Card Header -->
              <div class="bg-gradient-to-r from-green-500 to-emerald-600 px-6 py-4">
                <div class="flex items-center justify-between">
                  <div class="flex items-center space-x-3">
                    <div class="bg-white/20 rounded-full p-2">
                      <.icon name="hero-home-modern" class="h-5 w-5 text-white" />
                    </div>
                    <h3 class="text-xl font-bold text-white">
                      {greenhouse.id}
                    </h3>
                  </div>
                  <span class={[
                    "inline-flex items-center px-3 py-1 rounded-full text-xs font-semibold",
                    status_badge_class(greenhouse.status)
                  ]}>
                    <div class={[
                      "w-2 h-2 rounded-full mr-2",
                      status_dot_class(greenhouse.status)
                    ]}></div>
                    {format_status(greenhouse.status)}
                  </span>
                </div>
              </div>

              <!-- Card Body -->
              <div class="p-6">
                <!-- Metrics Grid -->
                <div class="grid grid-cols-3 gap-4 mb-6">
                  <!-- Temperature -->
                  <div class="text-center">
                    <div class="bg-red-50 rounded-full p-3 w-12 h-12 flex items-center justify-center mx-auto mb-2">
                      <.icon name="hero-fire" class="h-6 w-6 text-red-500" />
                    </div>
                    <p class="text-2xl font-bold text-red-600">{greenhouse.current_temperature}°</p>
                    <p class="text-xs text-gray-500 font-medium">Temperature</p>
                    <p class="text-xs text-gray-400 mt-1">
                      <%= if greenhouse.desired_temperature do %>
                        Target: {greenhouse.desired_temperature}°
                      <% else %>
                        <span class="italic">No target set</span>
                      <% end %>
                    </p>
                  </div>

                  <!-- Humidity -->
                  <div class="text-center">
                    <div class="bg-blue-50 rounded-full p-3 w-12 h-12 flex items-center justify-center mx-auto mb-2">
                      <.icon name="hero-cloud" class="h-6 w-6 text-blue-500" />
                    </div>
                    <p class="text-2xl font-bold text-blue-600">{greenhouse.current_humidity}%</p>
                    <p class="text-xs text-gray-500 font-medium">Humidity</p>
                    <p class="text-xs text-gray-400 mt-1">
                      <%= if greenhouse.desired_humidity do %>
                        Target: {greenhouse.desired_humidity}%
                      <% else %>
                        <span class="italic">No target set</span>
                      <% end %>
                    </p>
                  </div>

                  <!-- Light -->
                  <div class="text-center">
                    <div class="bg-yellow-50 rounded-full p-3 w-12 h-12 flex items-center justify-center mx-auto mb-2">
                      <.icon name="hero-sun" class="h-6 w-6 text-yellow-500" />
                    </div>
                    <p class="text-2xl font-bold text-yellow-600">{greenhouse.current_light}%</p>
                    <p class="text-xs text-gray-500 font-medium">Light</p>
                    <p class="text-xs text-gray-400 mt-1">
                      <%= if greenhouse.desired_light do %>
                        Target: {greenhouse.desired_light}%
                      <% else %>
                        <span class="italic">No target set</span>
                      <% end %>
                    </p>
                  </div>
                </div>

                <!-- Activity Info -->
                <div class="bg-gray-50 rounded-lg p-4 mb-4">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center space-x-2">
                      <.icon name="hero-chart-bar" class="h-4 w-4 text-gray-500" />
                      <span class="text-sm font-medium text-gray-700">Activity</span>
                    </div>
                    <span class="text-sm font-bold text-gray-900">{greenhouse.event_count} events</span>
                  </div>
                  <%= if greenhouse.last_updated do %>
                    <div class="flex items-center space-x-2 mt-2">
                      <.icon name="hero-clock" class="h-4 w-4 text-gray-400" />
                      <span class="text-xs text-gray-500">
                        Last updated: {format_time_ago(greenhouse.last_updated)}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
              </div>
            </.link>
          <% end %>
        </div>
      </div>
      
    <!-- Initialize Greenhouse Modal -->
      <.modal id="new-greenhouse-modal">
        <.simple_form for={%{}} phx-submit="initialize_greenhouse">
          <.input
            type="text"
            name="greenhouse_id"
            label="Greenhouse ID"
            placeholder="e.g., greenhouse-8"
            value=""
            required
          />
          <:actions>
            <.button class="w-full">Initialize Greenhouse</.button>
          </:actions>
        </.simple_form>
      </.modal>
    </div>
    """
  end

  defp load_greenhouses do
    require Logger
    # Get all greenhouse aggregates through Commanded
    # For now, we'll use a simple approach of known greenhouse IDs
    # In a real app, you might maintain a registry or use projections
    greenhouse_ids = API.list_greenhouses()
    #    Logger.info("Dashboard: Found greenhouse IDs: #{inspect(greenhouse_ids)}")

    greenhouses =
      greenhouse_ids
      |> Enum.map(&load_greenhouse_data/1)
      |> Enum.sort_by(& &1.id)

    #    Logger.info("Dashboard: Loaded #{length(greenhouses)} greenhouses: #{inspect(Enum.map(greenhouses, & &1.id))}")
    greenhouses
  end

  defp load_greenhouse_data(greenhouse_id) do
    case API.get_greenhouse_state(greenhouse_id) do
      {:ok, state} ->
        %{
          id: greenhouse_id,
          current_temperature: state.current_temperature,
          current_humidity: state.current_humidity,
          current_light: state.current_light,
          desired_temperature: state.desired_temperature,
          desired_humidity: state.desired_humidity,
          desired_light: state.desired_light,
          status: determine_status(state),
          event_count: state.event_count || 0,
          last_updated: state.last_updated
        }

      {:error, _} ->
        %{
          id: greenhouse_id,
          current_temperature: 0,
          current_humidity: 0,
          current_light: 0,
          desired_temperature: nil,
          desired_humidity: nil,
          desired_light: nil,
          status: :unknown,
          event_count: 0,
          last_updated: nil
        }
    end
  end

  defp determine_status(state) do
    cond do
      state.current_temperature == 0 and state.current_humidity == 0 and state.current_light == 0 ->
        :inactive

      needs_attention?(state) ->
        :warning

      true ->
        :active
    end
  end

  defp needs_attention?(state) do
    # Simple logic to determine if greenhouse needs attention
    (state.desired_temperature && abs(state.current_temperature - state.desired_temperature) > 5) ||
      (state.desired_humidity && abs(state.current_humidity - state.desired_humidity) > 20) ||
      (state.desired_light && abs(state.current_light - state.desired_light) > 30)
  end

  defp status_color_class(:active), do: "bg-green-100 text-green-800"
  defp status_color_class(:warning), do: "bg-yellow-100 text-yellow-800"
  defp status_color_class(:inactive), do: "bg-gray-100 text-gray-800"
  defp status_color_class(_), do: "bg-red-100 text-red-800"

  defp status_badge_class(:active), do: "bg-white/90 text-green-800 border border-green-200"
  defp status_badge_class(:warning), do: "bg-white/90 text-yellow-800 border border-yellow-200"
  defp status_badge_class(:inactive), do: "bg-white/90 text-gray-800 border border-gray-200"
  defp status_badge_class(_), do: "bg-white/90 text-red-800 border border-red-200"

  defp status_dot_class(:active), do: "bg-green-500"
  defp status_dot_class(:warning), do: "bg-yellow-500"
  defp status_dot_class(:inactive), do: "bg-gray-500"
  defp status_dot_class(_), do: "bg-red-500"

  defp format_status(:active), do: "Active"
  defp format_status(:warning), do: "Needs Attention"
  defp format_status(:inactive), do: "Inactive"
  defp format_status(_), do: "Unknown"

  defp calculate_avg_temperature(greenhouses) do
    if length(greenhouses) > 0 do
      total = Enum.sum(Enum.map(greenhouses, & &1.current_temperature))
      Float.round(total / length(greenhouses), 1)
    else
      0
    end
  end

  defp format_time_ago(nil), do: "Never"
  defp format_time_ago(datetime) do
    case DateTime.diff(DateTime.utc_now(), datetime, :second) do
      seconds when seconds < 60 -> "#{seconds}s ago"
      seconds when seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds when seconds < 86400 -> "#{div(seconds, 3600)}h ago"
      seconds -> "#{div(seconds, 86400)}d ago"
    end
  end
end
