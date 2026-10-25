defmodule PulseWeb.SetupLive do
  use PulseWeb, :live_view

  alias Pulse.Setup
  alias Pulse.Setup.EnergySource

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "My Devices")
      |> assign(:sources, Setup.list_all_energy_sources(user.id))
      |> assign(:form, nil)
      |> assign(:form_params, %{})
      |> assign(:editing_source, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:editing_source, nil) |> assign(:form, nil) |> assign(:form_params, %{})
  end

  defp apply_action(socket, :new, _params) do
    user = socket.assigns.current_user
    source = %EnergySource{user_id: user.id}
    changeset = Setup.change_energy_source(source)

    socket
    |> assign(:editing_source, nil)
    |> assign(:form_params, %{})
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    source = Setup.get_energy_source!(id)
    changeset = Setup.change_energy_source(source)

    socket
    |> assign(:editing_source, source)
    |> assign(:form_params, source_to_params(source))
    |> assign(:form, to_form(changeset))
  end

  @impl true
  def handle_event("validate", %{"energy_source" => params}, socket) do
    user = socket.assigns.current_user
    source = socket.assigns.editing_source || %EnergySource{user_id: user.id}
    merged_params = merge_energy_source_params(socket.assigns.form_params, params)
    changeset = Setup.change_energy_source(source, merged_params, validate_metadata: false)

    {:noreply,
     socket
     |> assign(:form_params, merged_params)
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"energy_source" => params}, socket) do
    user = socket.assigns.current_user
    params = merge_energy_source_params(socket.assigns.form_params, params)

    result =
      if source = socket.assigns.editing_source do
        Setup.update_energy_source(source, params)
      else
        Setup.create_energy_source(user.id, params)
      end

    case result do
      {:ok, _source} ->
        sources = Setup.list_all_energy_sources(user.id)

        socket =
          socket
          |> put_flash(:info, "Device saved successfully.")
          |> assign(:sources, sources)
          |> assign(:form, nil)
          |> assign(:form_params, %{})
          |> assign(:editing_source, nil)
          |> push_patch(to: ~p"/setup")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form_params, params)
         |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    source = Setup.get_energy_source!(id)
    Setup.delete_energy_source(source)
    sources = Setup.list_all_energy_sources(user.id)

    {:noreply,
     socket
     |> put_flash(:info, "Device deactivated.")
     |> assign(:sources, sources)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket |> assign(:form, nil) |> assign(:form_params, %{}) |> push_patch(to: ~p"/setup")}
  end

  defp merge_energy_source_params(existing, incoming) do
    Map.merge(existing || %{}, incoming || %{}, fn
      "metadata", left, right when is_map(left) and is_map(right) -> Map.merge(left, right)
      _key, _left, right -> right
    end)
  end

  defp source_to_params(source) do
    %{
      "name" => source.name,
      "source_type" => source.source_type,
      "unit" => source.unit,
      "active" => source.active,
      "metadata" => source.metadata || %{}
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp form_param(params, key), do: Map.get(params || %{}, key)

  defp metadata_param(params, key) do
    params
    |> form_param("metadata")
    |> case do
      metadata when is_map(metadata) -> Map.get(metadata, key)
      _ -> nil
    end
  end

  defp metadata_field_name(form, key) do
    "#{form[:metadata].name}[#{key}]"
  end

  defp metadata_field_id(form, key) do
    "#{form[:metadata].id}_#{key}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">My Devices</h1>
        <.link
          patch={~p"/setup/new"}
          class="bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-green-700 transition"
        >
          + Add device
        </.link>
      </div>

      <%!-- Modal form --%>
      <.modal :if={@form} id="source-form-modal" show={true} on_cancel={JS.push("close_form")}>
        <h2 class="text-lg font-semibold text-gray-900 mb-4">
          {if @editing_source, do: "Edit device", else: "Add new device"}
        </h2>
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
          <.input
            field={@form[:name]}
            value={form_param(@form_params, "name")}
            label="Name"
            placeholder="e.g. Home Electricity, VW Golf"
          />
          <.select
            field={@form[:source_type]}
            value={form_param(@form_params, "source_type")}
            label="Type"
            options={[
              "Select type": "",
              Electricity: "electricity",
              Gas: "gas",
              Fuel: "fuel",
              Water: "water",
              Heating: "heating"
            ]}
          />

          <%!-- Dynamic metadata fields based on type — rendered in template for clarity --%>
          <%= case form_param(@form_params, "source_type") || Phoenix.HTML.Form.input_value(@form, :source_type) do %>
            <% "electricity" -> %>
              <.input
                id={metadata_field_id(@form, "tariff_kwh")}
                name={metadata_field_name(@form, "tariff_kwh")}
                value={metadata_param(@form_params, "tariff_kwh")}
                label="Tariff ($/kWh)"
                help="The variable price you pay for each kilowatt-hour of electricity, in dollars. Find it on your electricity bill. Exclude fixed monthly charges; use a blended rate if prices vary. This affects cost estimates, not energy use."
                type="number"
                step="0.001"
                placeholder="0.15"
              />
              <.input
                id={metadata_field_id(@form, "rated_kw")}
                name={metadata_field_name(@form, "rated_kw")}
                value={metadata_param(@form_params, "rated_kw")}
                label="Rated power (kW)"
                help="Power drawn while this device runs, from its label or specification. 1 kW = 1,000 watts; a 100 W device is 0.1 kW. Actual draw can vary with load."
                type="number"
                step="0.1"
                placeholder="2.5"
              />
            <% "gas" -> %>
              <.input
                id={metadata_field_id(@form, "cost_per_cubic_meter")}
                name={metadata_field_name(@form, "cost_per_cubic_meter")}
                value={metadata_param(@form_params, "cost_per_cubic_meter")}
                label="Cost per m³ ($)"
                help="Your billed price per cubic meter, excluding fixed charges. Check the units on your bill before entering it."
                type="number"
                step="0.001"
                placeholder="0.08"
              />
              <.input
                id={metadata_field_id(@form, "rated_output_kw")}
                name={metadata_field_name(@form, "rated_output_kw")}
                value={metadata_param(@form_params, "rated_output_kw")}
                label="Boiler output (kW)"
                help="Useful heat output at rated load. Input energy can be higher because the boiler loses heat."
                type="number"
                step="0.1"
                placeholder="24"
              />
              <.input
                id={metadata_field_id(@form, "calorific_value")}
                name={metadata_field_name(@form, "calorific_value")}
                value={metadata_param(@form_params, "calorific_value")}
                label="Calorific value (MJ/m³)"
                help="Energy in each cubic meter of gas. Use the value from your gas supplier; it varies by gas composition. 3.6 MJ = 1 kWh."
                type="number"
                step="0.1"
                placeholder="38.5"
              />
            <% "fuel" -> %>
              <.select
                id={metadata_field_id(@form, "fuel_type")}
                name={metadata_field_name(@form, "fuel_type")}
                value={metadata_param(@form_params, "fuel_type")}
                label="Fuel type"
                options={[Petrol: "petrol", Diesel: "diesel", Hybrid: "hybrid", Electric: "electric"]}
              />
              <.input
                id={metadata_field_id(@form, "consumption_per_100km")}
                name={metadata_field_name(@form, "consumption_per_100km")}
                value={metadata_param(@form_params, "consumption_per_100km")}
                label="Consumption (L/100km)"
                help="Liters of fuel used to travel 100 km. Prefer your own refueling history over the advertised test-cycle figure."
                type="number"
                step="0.1"
                placeholder="7.5"
              />
              <.input
                id={metadata_field_id(@form, "cost_per_liter")}
                name={metadata_field_name(@form, "cost_per_liter")}
                value={metadata_param(@form_params, "cost_per_liter")}
                label="Cost per liter ($)"
                help="Fuel price per liter in dollars, used for cost estimates."
                type="number"
                step="0.001"
                placeholder="1.65"
              />
            <% "water" -> %>
              <.input
                id={metadata_field_id(@form, "cost_per_cubic_meter")}
                name={metadata_field_name(@form, "cost_per_cubic_meter")}
                value={metadata_param(@form_params, "cost_per_cubic_meter")}
                label="Cost per m³ ($)"
                help="Your billed price per cubic meter, excluding fixed charges. Check the units on your bill before entering it."
                type="number"
                step="0.001"
                placeholder="2.50"
              />
            <% "heating" -> %>
              <.input
                id={metadata_field_id(@form, "rated_output_kw")}
                name={metadata_field_name(@form, "rated_output_kw")}
                value={metadata_param(@form_params, "rated_output_kw")}
                label="Rated output (kW)"
                help="Useful heating power while operating at rated load; average use depends on runtime and load."
                type="number"
                step="0.1"
                placeholder="18"
              />
              <.input
                id={metadata_field_id(@form, "boiler_efficiency")}
                name={metadata_field_name(@form, "boiler_efficiency")}
                value={metadata_param(@form_params, "boiler_efficiency")}
                label="Boiler efficiency (0–1)"
                help="Share of fuel energy delivered as useful heat. Enter 0.9 for 90%. Use a consistent heating-value basis with your fuel specification."
                type="number"
                step="0.01"
                placeholder="0.90"
              />
            <% _ -> %>
          <% end %>

          <div class="flex gap-3 pt-2">
            <.button type="submit" variant={:primary}>Save</.button>
            <.button type="button" variant={:secondary} phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>

      <%!-- Sources list --%>
      <div
        :if={@sources != []}
        class="bg-white rounded-xl shadow-sm border border-gray-100 divide-y divide-gray-100"
      >
        <div :for={source <- @sources} class="flex items-center justify-between p-4">
          <div class="flex items-center gap-3">
            <.source_badge source_type={source.source_type} />
            <div>
              <p class="font-medium text-gray-900">{source.name}</p>
              <p class="text-xs text-gray-400">{if source.active, do: "Active", else: "Inactive"}</p>
            </div>
          </div>
          <div class="flex gap-2">
            <.link
              patch={~p"/setup/#{source.id}/edit"}
              class="text-sm text-gray-500 hover:text-gray-900"
            >
              Edit
            </.link>
            <button
              phx-click="delete"
              phx-value-id={source.id}
              data-confirm="Deactivate this device?"
              class="text-sm text-red-400 hover:text-red-600"
            >
              Remove
            </button>
          </div>
        </div>
      </div>

      <div :if={@sources == []} class="text-center py-16 text-gray-400">
        <p class="text-4xl mb-3">🔌</p>
        <p class="font-medium text-gray-600">No devices yet</p>
        <p class="text-sm mt-1">Add your first device to start tracking.</p>
      </div>
    </div>
    """
  end
end
