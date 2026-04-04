defmodule PulseWeb.SettingsLive do
  use PulseWeb, :live_view

  alias Pulse.{Accounts, Notifications}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    rules = Notifications.list_rules(user.id)

    settings_form =
      Accounts.update_user_settings(user, %{})
      |> case do
        _ -> to_form(Accounts.change_user_settings(user))
      end

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:rules, rules)
     |> assign(:settings_form, settings_form)
     |> assign(:rule_form, to_form(Notifications.new_rule_changeset()))}
  end

  @impl true
  def handle_event("save_settings", %{"user" => params}, socket) do
    user = socket.assigns.current_user

    case Accounts.update_user_settings(user, params) do
      {:ok, _user} ->
        {:noreply, put_flash(socket, :info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  def handle_event("toggle_rule", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))
    Notifications.toggle_rule(rule)
    rules = Notifications.list_rules(socket.assigns.current_user.id)
    {:noreply, assign(socket, :rules, rules)}
  end

  def handle_event("delete_rule", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))
    Notifications.delete_rule(rule)
    rules = Notifications.list_rules(socket.assigns.current_user.id)
    {:noreply, assign(socket, :rules, rules)}
  end

  def handle_event("save_rule", %{"notification_rule" => params}, socket) do
    user = socket.assigns.current_user

    case Notifications.create_rule(user.id, params) do
      {:ok, _rule} ->
        rules = Notifications.list_rules(user.id)

        {:noreply,
         socket
         |> assign(:rules, rules)
         |> assign(:rule_form, to_form(Notifications.new_rule_changeset()))
         |> put_flash(:info, "Alert rule added.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :rule_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl space-y-8">
      <h1 class="text-2xl font-bold text-gray-900">Settings</h1>

      <%# Account settings %>
      <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <h2 class="font-semibold text-gray-900 mb-4">Account</h2>
        <.form for={@settings_form} phx-submit="save_settings" class="space-y-4">
          <.input field={@settings_form[:timezone]} label="Timezone" placeholder="Europe/London" />
          <.button type="submit" variant={:primary}>Save</.button>
        </.form>
      </div>

      <%# Notification rules %>
      <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <h2 class="font-semibold text-gray-900 mb-4">Alert rules</h2>

        <div :if={@rules != []} class="divide-y divide-gray-100 mb-4">
          <div :for={rule <- @rules} class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= rule.rule_type |> String.replace("_", " ") |> String.capitalize() %>
              </p>
              <p class="text-xs text-gray-500">Threshold: <%= rule.threshold_value %></p>
            </div>
            <div class="flex gap-3 items-center">
              <button
                phx-click="toggle_rule"
                phx-value-id={rule.id}
                class={["text-xs px-2 py-1 rounded", rule.enabled && "bg-green-100 text-green-700", not rule.enabled && "bg-gray-100 text-gray-500"]}
              >
                <%= if rule.enabled, do: "On", else: "Off" %>
              </button>
              <button phx-click="delete_rule" phx-value-id={rule.id} class="text-xs text-red-400 hover:text-red-600">
                Delete
              </button>
            </div>
          </div>
        </div>

        <.form for={@rule_form} phx-submit="save_rule" class="space-y-3">
          <.select
            field={@rule_form[:rule_type]}
            label="Alert type"
            options={[
              "Select type": "",
              "Daily cost exceeds": "threshold_daily_cost",
              "Weekly cost exceeds": "threshold_weekly_cost",
              "Daily kWh exceeds": "threshold_kwh"
            ]}
          />
          <.input field={@rule_form[:threshold_value]} label="Threshold value ($)" type="number" step="0.01" />
          <.button type="submit" variant={:secondary}>Add alert</.button>
        </.form>
      </div>
    </div>
    """
  end
end
