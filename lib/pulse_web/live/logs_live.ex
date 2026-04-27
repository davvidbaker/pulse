defmodule PulseWeb.LogsLive do
  use PulseWeb, :live_view

  alias Pulse.{Logs, Setup}
  alias Pulse.Logs.UsageLog

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Pulse.PubSub, "user:#{user.id}:log_computed")
    end

    sources = Setup.list_energy_sources(user.id)
    logs = Logs.list_logs(user.id)

    form_changeset = Logs.new_log_changeset()

    socket =
      socket
      |> assign(:page_title, "Log Usage")
      |> assign(:sources, sources)
      |> assign(:logs, logs)
      |> assign(:form, to_form(form_changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"usage_log" => params}, socket) do
    changeset = Logs.new_log_changeset(params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"usage_log" => params}, socket) do
    user = socket.assigns.current_user

    case Logs.log_usage(user.id, params) do
      {:ok, _log} ->
        logs = Logs.list_logs(user.id)
        form = to_form(Logs.new_log_changeset())

        {:noreply,
         socket
         |> assign(:logs, logs)
         |> assign(:form, form)
         |> put_flash(:info, "Usage logged! Cost is being calculated…")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Logs.get_log(user.id, id) do
      nil ->
        {:noreply, socket}

      log ->
        Logs.delete_log(log)
        logs = Logs.list_logs(user.id)
        {:noreply, assign(socket, :logs, logs)}
    end
  end

  @impl true
  def handle_info({:log_computed, log_id}, socket) do
    # Reload the specific log to show computed cost
    logs =
      Enum.map(socket.assigns.logs, fn l ->
        if l.id == log_id, do: Logs.get_log!(log_id), else: l
      end)

    {:noreply, assign(socket, :logs, logs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-gray-900">Log Usage</h1>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%# Quick log form %>
        <div class="lg:col-span-1">
          <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-5">
            <h2 class="font-semibold text-gray-800 mb-4">Quick log</h2>

            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.select
                field={@form[:energy_source_id]}
                label="Device"
                options={[{"Select device", ""} | Enum.map(@sources, &{&1.name, &1.id})]}
              />

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Input type</label>
                <div class="flex gap-3">
                  <label class="flex items-center gap-1.5 text-sm">
                    <input type="radio" name="usage_log[input_type]" value="duration"
                      checked={Phoenix.HTML.Form.input_value(@form, :input_type) != "quantity"} />
                    Duration
                  </label>
                  <label class="flex items-center gap-1.5 text-sm">
                    <input type="radio" name="usage_log[input_type]" value="quantity" />
                    Quantity
                  </label>
                </div>
              </div>

              <%= if Phoenix.HTML.Form.input_value(@form, :input_type) == "quantity" do %>
                <.input field={@form[:quantity]} label="Quantity" type="number" step="0.01" placeholder="e.g. 0.5 m³" />
              <% else %>
                <.input field={@form[:duration_minutes]} label="Duration (minutes)" type="number" min="1" placeholder="e.g. 30" />
              <% end %>

              <.input field={@form[:logged_at]} label="When" type="datetime-local" />
              <.input field={@form[:notes]} label="Notes (optional)" placeholder="Any context…" />

              <.button type="submit" variant={:primary} class="w-full">Log usage</.button>
            </.form>
          </div>
        </div>

        <%# Logs list %>
        <div class="lg:col-span-2">
          <div class="bg-white rounded-xl shadow-sm border border-gray-100">
            <div class="p-4 border-b border-gray-100">
              <h2 class="font-semibold text-gray-800">Recent logs</h2>
            </div>

            <div :if={@logs == []} class="text-center py-12 text-gray-400">
              <p class="text-3xl mb-2">📋</p>
              <p class="text-sm">No usage logs yet.</p>
            </div>

            <div class="divide-y divide-gray-50">
              <div :for={log <- @logs} class="flex items-center justify-between p-4 hover:bg-gray-50">
                <div class="flex items-center gap-3">
                  <.source_badge source_type={log.energy_source && log.energy_source.source_type} />
                  <div>
                    <p class="text-sm font-medium text-gray-900">
                      <%= log.energy_source && log.energy_source.name %>
                    </p>
                    <p class="text-xs text-gray-400">
                      <%= if log.input_type == "duration" do %>
                        <%= log.duration_minutes %> min
                      <% else %>
                        <%= log.quantity %> units
                      <% end %>
                      · <%= Calendar.strftime(log.logged_at, "%b %d, %H:%M") %>
                    </p>
                    <p :if={log.notes} class="text-xs text-gray-400 italic"><%= log.notes %></p>
                  </div>
                </div>
                <div class="flex items-center gap-4">
                  <div class="text-right">
                    <%= if log.computed_cost do %>
                      <p class="text-sm font-semibold text-gray-900">$<%= Decimal.round(log.computed_cost, 3) %></p>
                      <p class="text-xs text-gray-400"><%= Decimal.round(log.computed_kwh, 3) %> kWh</p>
                    <% else %>
                      <p class="text-xs text-gray-400 animate-pulse">Calculating…</p>
                    <% end %>
                  </div>
                  <button
                    phx-click="delete"
                    phx-value-id={log.id}
                    data-confirm="Delete this log?"
                    class="text-gray-300 hover:text-red-400 text-sm"
                  >
                    ✕
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
