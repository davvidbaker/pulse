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
      |> assign(:editing_source, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:editing_source, nil) |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Setup.change_energy_source(%EnergySource{})
    socket |> assign(:editing_source, nil) |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    source = Setup.get_energy_source!(id)
    changeset = Setup.change_energy_source(source)
    socket |> assign(:editing_source, source) |> assign(:form, to_form(changeset))
  end

  @impl true
  def handle_event("validate", %{"energy_source" => params}, socket) do
    source = socket.assigns.editing_source || %EnergySource{}
    changeset = Setup.change_energy_source(source, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"energy_source" => params}, socket) do
    user = socket.assigns.current_user

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
          |> assign(:editing_source, nil)
          |> push_patch(to: ~p"/setup")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
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
    {:noreply, socket |> assign(:form, nil) |> push_patch(to: ~p"/setup")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">My Devices</h1>
        <.link patch={~p"/setup/new"} class="bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-green-700 transition">
          + Add device
        </.link>
      </div>

      <%# Modal form %>
      <.modal :if={@form} id="source-form-modal" show={true} on_cancel={JS.push("close_form")}>
        <h2 class="text-lg font-semibold text-gray-900 mb-4">
          <%= if @editing_source, do: "Edit device", else: "Add new device" %>
        </h2>
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
          <.input field={@form[:name]} label="Name" placeholder="e.g. Home Electricity, VW Golf" />
          <.select
            field={@form[:source_type]}
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

          <%# Dynamic metadata fields based on type — rendered in template for clarity %>
          <%= case Phoenix.HTML.Form.input_value(@form, :source_type) do %>
            <% "electricity" -> %>
              <.input field={@form[:metadata]["tariff_kwh"]} label="Tariff ($/kWh)" type="number" step="0.001" placeholder="0.15" />
              <.input field={@form[:metadata]["rated_kw"]} label="Rated power (kW)" type="number" step="0.1" placeholder="2.5" />

            <% "gas" -> %>
              <.input field={@form[:metadata]["cost_per_cubic_meter"]} label="Cost per m³ ($)" type="number" step="0.001" placeholder="0.08" />
              <.input field={@form[:metadata]["rated_output_kw"]} label="Boiler output (kW)" type="number" step="0.1" placeholder="24" />
              <.input field={@form[:metadata]["calorific_value"]} label="Calorific value (MJ/m³)" type="number" step="0.1" placeholder="38.5" />

            <% "fuel" -> %>
              <.select field={@form[:metadata]["fuel_type"]} label="Fuel type"
                options={[Petrol: "petrol", Diesel: "diesel", Hybrid: "hybrid", Electric: "electric"]} />
              <.input field={@form[:metadata]["consumption_per_100km"]} label="Consumption (L/100km)" type="number" step="0.1" placeholder="7.5" />
              <.input field={@form[:metadata]["cost_per_liter"]} label="Cost per liter ($)" type="number" step="0.001" placeholder="1.65" />

            <% "water" -> %>
              <.input field={@form[:metadata]["cost_per_cubic_meter"]} label="Cost per m³ ($)" type="number" step="0.001" placeholder="2.50" />

            <% "heating" -> %>
              <.input field={@form[:metadata]["rated_output_kw"]} label="Rated output (kW)" type="number" step="0.1" placeholder="18" />
              <.input field={@form[:metadata]["boiler_efficiency"]} label="Boiler efficiency (0–1)" type="number" step="0.01" placeholder="0.90" />

            <% _ -> %>
          <% end %>

          <div class="flex gap-3 pt-2">
            <.button type="submit" variant={:primary}>Save</.button>
            <.button type="button" variant={:secondary} phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>

      <%# Sources list %>
      <div :if={@sources != []} class="bg-white rounded-xl shadow-sm border border-gray-100 divide-y divide-gray-100">
        <div :for={source <- @sources} class="flex items-center justify-between p-4">
          <div class="flex items-center gap-3">
            <.source_badge source_type={source.source_type} />
            <div>
              <p class="font-medium text-gray-900"><%= source.name %></p>
              <p class="text-xs text-gray-400"><%= if source.active, do: "Active", else: "Inactive" %></p>
            </div>
          </div>
          <div class="flex gap-2">
            <.link patch={~p"/setup/#{source.id}/edit"} class="text-sm text-gray-500 hover:text-gray-900">
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
