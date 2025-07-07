defmodule RegulateGreenhouseWeb.GreenhouseLive do
  use RegulateGreenhouseWeb, :live_view
  
  alias RegulateGreenhouse.API

  @impl true
  def mount(%{"id" => greenhouse_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time greenhouse updates
      Phoenix.PubSub.subscribe(RegulateGreenhouse.PubSub, "greenhouse_updates")
      # Refresh data every 2 seconds as fallback
      :timer.send_interval(2000, self(), :refresh)
    end

    socket = 
      socket
      |> assign(:greenhouse_id, greenhouse_id)
      |> assign(:page_title, "Greenhouse #{greenhouse_id}")
      |> load_greenhouse_data()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_greenhouse_data(socket)}
  end

  @impl true
  def handle_info({:greenhouse_created, read_model}, socket) do
    # Only update if this is the greenhouse we're viewing
    if read_model.greenhouse_id == socket.assigns.greenhouse_id do
      {:noreply, load_greenhouse_data(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:greenhouse_updated, read_model, _event_type}, socket) do
    # Only update if this is the greenhouse we're viewing
    if read_model.greenhouse_id == socket.assigns.greenhouse_id do
      {:noreply, load_greenhouse_data(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_desired_temperature", %{"temperature" => temp_str}, socket) do
    case Float.parse(temp_str) do
      {temperature, _} ->
        case API.set_desired_temperature(socket.assigns.greenhouse_id, temperature) do
          :ok ->
            socket = 
              socket
              |> put_flash(:info, "Desired temperature set to #{temperature}°C")
              |> load_greenhouse_data()
            {:noreply, socket}
          
          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to set temperature: #{inspect(reason)}")
            {:noreply, socket}
        end
      
      :error ->
        socket = put_flash(socket, :error, "Invalid temperature value")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_desired_humidity", %{"humidity" => humidity_str}, socket) do
    case Float.parse(humidity_str) do
      {humidity, _} ->
        case API.set_desired_humidity(socket.assigns.greenhouse_id, humidity) do
          :ok ->
            socket = 
              socket
              |> put_flash(:info, "Desired humidity set to #{humidity}%")
              |> load_greenhouse_data()
            {:noreply, socket}
          
          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to set humidity: #{inspect(reason)}")
            {:noreply, socket}
        end
      
      :error ->
        socket = put_flash(socket, :error, "Invalid humidity value")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_desired_light", %{"light" => light_str}, socket) do
    case Float.parse(light_str) do
      {light, _} ->
        case API.set_desired_light(socket.assigns.greenhouse_id, light) do
          :ok ->
            socket = 
              socket
              |> put_flash(:info, "Desired light set to #{light}%")
              |> load_greenhouse_data()
            {:noreply, socket}
          
          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to set light: #{inspect(reason)}")
            {:noreply, socket}
        end
      
      :error ->
        socket = put_flash(socket, :error, "Invalid light value")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("simulate_measurement", %{"type" => measurement_type}, socket) do
    result = case measurement_type do
      "temperature" -> 
        value = 15 + :rand.uniform(20)
        API.measure_temperature(socket.assigns.greenhouse_id, value)
      "humidity" -> 
        value = 30 + :rand.uniform(40)
        API.measure_humidity(socket.assigns.greenhouse_id, value)
      "light" -> 
        value = 20 + :rand.uniform(60)
        API.measure_light(socket.assigns.greenhouse_id, value)
    end
    
    case result do
      :ok ->
        socket = 
          socket
          |> put_flash(:info, "Simulated #{measurement_type} measurement")
          |> load_greenhouse_data()
        {:noreply, socket}
      
      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to simulate measurement: #{inspect(reason)}")
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
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center">
              <.link navigate={~p"/"} class="text-green-600 hover:text-green-700 mr-4">
                <.icon name="hero-arrow-left" class="h-6 w-6" />
              </.link>
              <.icon name="hero-home-modern" class="h-8 w-8 text-green-600 mr-3" />
              <h1 class="text-2xl font-bold text-gray-900">
                Greenhouse <%= @greenhouse_id %>
              </h1>
            </div>
            <div class="flex items-center space-x-2">
              <span class={[
                "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
                status_color_class(@greenhouse.status)
              ]}>
                <%= @greenhouse.status %>
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Current Readings -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-medium text-gray-900">Current Readings</h2>
              </div>
              <div class="p-6">
                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <!-- Temperature -->
                  <div class="text-center">
                    <div class="mx-auto w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mb-4">
                      <.icon name="hero-thermometer" class="h-8 w-8 text-red-600" />
                    </div>
                    <h3 class="text-lg font-medium text-gray-900">Temperature</h3>
                    <p class="text-3xl font-bold text-red-600 mt-2">
                      <%= @greenhouse.current_temperature %>°C
                    </p>
                    <%= if @greenhouse.desired_temperature do %>
                      <p class="text-sm text-gray-500 mt-1">
                        Target: <%= @greenhouse.desired_temperature %>°C
                      </p>
                    <% end %>
                  </div>

                  <!-- Humidity -->
                  <div class="text-center">
                    <div class="mx-auto w-16 h-16 bg-blue-100 rounded-full flex items-center justify-center mb-4">
                      <.icon name="hero-cloud" class="h-8 w-8 text-blue-600" />
                    </div>
                    <h3 class="text-lg font-medium text-gray-900">Humidity</h3>
                    <p class="text-3xl font-bold text-blue-600 mt-2">
                      <%= @greenhouse.current_humidity %>%
                    </p>
                    <%= if @greenhouse.desired_humidity do %>
                      <p class="text-sm text-gray-500 mt-1">
                        Target: <%= @greenhouse.desired_humidity %>%
                      </p>
                    <% end %>
                  </div>

                  <!-- Light -->
                  <div class="text-center">
                    <div class="mx-auto w-16 h-16 bg-yellow-100 rounded-full flex items-center justify-center mb-4">
                      <.icon name="hero-sun" class="h-8 w-8 text-yellow-600" />
                    </div>
                    <h3 class="text-lg font-medium text-gray-900">Light</h3>
                    <p class="text-3xl font-bold text-yellow-600 mt-2">
                      <%= @greenhouse.current_light %>%
                    </p>
                    <%= if @greenhouse.desired_light do %>
                      <p class="text-sm text-gray-500 mt-1">
                        Target: <%= @greenhouse.desired_light %>%
                      </p>
                    <% end %>
                  </div>
                </div>

                <!-- Simulation Controls -->
                <div class="mt-8 border-t border-gray-200 pt-6">
                  <h3 class="text-lg font-medium text-gray-900 mb-4">Simulate Sensor Readings</h3>
                  <div class="flex flex-wrap gap-2">
                    <.button 
                      phx-click="simulate_measurement" 
                      phx-value-type="temperature"
                      class="bg-red-600 hover:bg-red-700 text-white"
                    >
                      Simulate Temperature
                    </.button>
                    <.button 
                      phx-click="simulate_measurement" 
                      phx-value-type="humidity"
                      class="bg-blue-600 hover:bg-blue-700 text-white"
                    >
                      Simulate Humidity
                    </.button>
                    <.button 
                      phx-click="simulate_measurement" 
                      phx-value-type="light"
                      class="bg-yellow-600 hover:bg-yellow-700 text-white"
                    >
                      Simulate Light
                    </.button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Controls -->
          <div>
            <div class="bg-white shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-medium text-gray-900">Set Desired Values</h2>
              </div>
              <div class="p-6 space-y-6">
                <!-- Temperature Control -->
                <div>
                  <.simple_form for={%{}} phx-submit="set_desired_temperature">
                    <.input 
                      type="number" 
                      name="temperature" 
                      label="Desired Temperature (°C)" 
                      value={@greenhouse.desired_temperature}
                      step="0.1"
                      min="0"
                      max="50"
                    />
                    <:actions>
                      <.button class="w-full bg-red-600 hover:bg-red-700 text-white">
                        Set Temperature
                      </.button>
                    </:actions>
                  </.simple_form>
                </div>

                <!-- Humidity Control -->
                <div>
                  <.simple_form for={%{}} phx-submit="set_desired_humidity">
                    <.input 
                      type="number" 
                      name="humidity" 
                      label="Desired Humidity (%)" 
                      value={@greenhouse.desired_humidity}
                      step="1"
                      min="0"
                      max="100"
                    />
                    <:actions>
                      <.button class="w-full bg-blue-600 hover:bg-blue-700 text-white">
                        Set Humidity
                      </.button>
                    </:actions>
                  </.simple_form>
                </div>

                <!-- Light Control -->
                <div>
                  <.simple_form for={%{}} phx-submit="set_desired_light">
                    <.input 
                      type="number" 
                      name="light" 
                      label="Desired Light (%)" 
                      value={@greenhouse.desired_light}
                      step="1"
                      min="0"
                      max="100"
                    />
                    <:actions>
                      <.button class="w-full bg-yellow-600 hover:bg-yellow-700 text-white">
                        Set Light
                      </.button>
                    </:actions>
                  </.simple_form>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Recent Events -->
        <div class="mt-8">
          <div class="bg-white shadow rounded-lg">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-lg font-medium text-gray-900">Recent Events</h2>
            </div>
            <div class="p-6">
              <%= if length(@greenhouse.events) > 0 do %>
                <div class="space-y-4">
                  <%= for event <- Enum.take(@greenhouse.events, 10) do %>
                    <div class="flex items-start space-x-3">
                      <div class="flex-shrink-0">
                        <div class={[
                          "w-3 h-3 rounded-full mt-1",
                          event_type_color(event.event_type)
                        ]}></div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-gray-900">
                          <%= format_event_type(event.event_type) %>
                        </p>
                        <p class="text-sm text-gray-500">
                          <%= format_event_data(event) %>
                        </p>
                        <p class="text-xs text-gray-400 mt-1">
                          <%= format_timestamp(event.created) %>
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-gray-500 text-center py-8">No events recorded yet</p>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_greenhouse_data(socket) do
    greenhouse_id = socket.assigns.greenhouse_id
    
    case API.get_greenhouse_state(greenhouse_id) do
      {:ok, state} ->
        # Get recent events for display
        events = API.get_greenhouse_events(greenhouse_id, 20) || []
        
        greenhouse = %{
          id: greenhouse_id,
          current_temperature: state.current_temperature,
          current_humidity: state.current_humidity,
          current_light: state.current_light,
          desired_temperature: state.desired_temperature,
          desired_humidity: state.desired_humidity,
          desired_light: state.desired_light,
          status: determine_status(state),
          events: events,
          last_updated: state.last_updated
        }
        
        assign(socket, :greenhouse, greenhouse)
      
      {:error, _} ->
        greenhouse = %{
          id: greenhouse_id,
          current_temperature: 0,
          current_humidity: 0,
          current_light: 0,
          desired_temperature: nil,
          desired_humidity: nil,
          desired_light: nil,
          status: :unknown,
          events: [],
          last_updated: nil
        }
        
        assign(socket, :greenhouse, greenhouse)
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
    (state.desired_temperature && abs(state.current_temperature - state.desired_temperature) > 5) ||
    (state.desired_humidity && abs(state.current_humidity - state.desired_humidity) > 20) ||
    (state.desired_light && abs(state.current_light - state.desired_light) > 30)
  end

  defp status_color_class(:active), do: "bg-green-100 text-green-800"
  defp status_color_class(:warning), do: "bg-yellow-100 text-yellow-800"
  defp status_color_class(:inactive), do: "bg-gray-100 text-gray-800"
  defp status_color_class(_), do: "bg-red-100 text-red-800"



  defp event_type_color("initialized:v1"), do: "bg-green-400"
  defp event_type_color("temperature_measured:v1"), do: "bg-red-400"
  defp event_type_color("humidity_measured:v1"), do: "bg-blue-400"
  defp event_type_color("light_measured:v1"), do: "bg-yellow-400"
  defp event_type_color("desired_temperature_set:v1"), do: "bg-red-600"
  defp event_type_color("desired_humidity_set:v1"), do: "bg-blue-600"
  defp event_type_color("desired_light_set:v1"), do: "bg-yellow-600"
  defp event_type_color(_), do: "bg-gray-400"

  defp format_event_type("initialized:v1"), do: "Greenhouse Initialized"
  defp format_event_type("temperature_measured:v1"), do: "Temperature Measured"
  defp format_event_type("humidity_measured:v1"), do: "Humidity Measured"
  defp format_event_type("light_measured:v1"), do: "Light Measured"
  defp format_event_type("desired_temperature_set:v1"), do: "Desired Temperature Set"
  defp format_event_type("desired_humidity_set:v1"), do: "Desired Humidity Set"
  defp format_event_type("desired_light_set:v1"), do: "Desired Light Set"
  defp format_event_type(type), do: type

  defp format_event_data(event) do
    case event.event_type do
      "temperature_measured:v1" -> "#{event.data["temperature"]}°C"
      "humidity_measured:v1" -> "#{event.data["humidity"]}%"
      "light_measured:v1" -> "#{event.data["light"]}%"
      "desired_temperature_set:v1" -> "Target: #{event.data["temperature"]}°C"
      "desired_humidity_set:v1" -> "Target: #{event.data["humidity"]}%"
      "desired_light_set:v1" -> "Target: #{event.data["light"]}%"
      "initialized:v1" -> 
        "T: #{event.data["temperature"]}°C, H: #{event.data["humidity"]}%, L: #{event.data["light"]}%"
      _ -> 
        inspect(event.data)
    end
  end

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> 
        dt
        |> DateTime.shift_zone!("Etc/UTC")
        |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
      
      _ -> 
        timestamp
    end
  end

  defp format_timestamp(timestamp), do: inspect(timestamp)
end
