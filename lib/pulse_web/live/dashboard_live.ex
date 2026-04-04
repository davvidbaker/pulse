defmodule PulseWeb.DashboardLive do
  use PulseWeb, :live_view

  alias Pulse.{Summaries, Suggestions, Notifications}

  @periods [:day, :week, :month]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Pulse.PubSub, "user:#{user.id}:log_computed")
      Phoenix.PubSub.subscribe(Pulse.PubSub, "user:#{user.id}:notifications")
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:period, :week)
      |> assign(:unread_count, Notifications.unread_count(user.id))
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    period = String.to_existing_atom(period)

    if period in @periods do
      {:noreply, socket |> assign(:period, period) |> load_data()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_suggestion", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    Suggestions.dismiss_suggestion(user.id, id)

    suggestions = Enum.reject(socket.assigns.suggestions, &(&1.id == id))
    {:noreply, assign(socket, :suggestions, suggestions)}
  end

  @impl true
  def handle_info({:log_computed, _log_id}, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_info({:new_notification, _notification}, socket) do
    user = socket.assigns.current_user
    {:noreply, assign(socket, :unread_count, Notifications.unread_count(user.id))}
  end

  defp load_data(socket) do
    user = socket.assigns.current_user
    period = socket.assigns.period
    today = Date.utc_today()

    {from_date, to_date} =
      case period do
        :day ->
          {today, today}

        :week ->
          week_start = Date.add(today, -Date.day_of_week(today) + 1)
          {week_start, today}

        :month ->
          {Date.beginning_of_month(today), today}
      end

    summaries = Summaries.list_summaries(user.id, from_date, to_date)
    suggestions = Suggestions.list_active_suggestions(user.id)

    total_cost =
      Enum.reduce(summaries, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_cost) end)

    total_kwh =
      Enum.reduce(summaries, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_kwh) end)

    chart_data = build_chart_data(summaries)

    socket
    |> assign(:summaries, summaries)
    |> assign(:suggestions, suggestions)
    |> assign(:total_cost, total_cost)
    |> assign(:total_kwh, total_kwh)
    |> assign(:chart_data, chart_data)
    |> push_event("chart_data_updated", %{data: chart_data})
  end

  defp build_chart_data(summaries) do
    %{
      labels: Enum.map(summaries, &Date.to_iso8601(&1.date)),
      costs: Enum.map(summaries, &Decimal.to_float(&1.total_cost)),
      kwh: Enum.map(summaries, &Decimal.to_float(&1.total_kwh))
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%# Header %>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p class="text-gray-500 text-sm">Hi <%= @current_user.email %></p>
        </div>
        <div class="flex gap-2">
          <button
            :for={p <- [:day, :week, :month]}
            phx-click="change_period"
            phx-value-period={p}
            class={[
              "px-3 py-1.5 rounded-lg text-sm font-medium transition",
              @period == p && "bg-green-600 text-white",
              @period != p && "bg-white border border-gray-300 text-gray-600 hover:bg-gray-50"
            ]}
          >
            <%= String.capitalize(to_string(p)) %>
          </button>
        </div>
      </div>

      <%# Stats row %>
      <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
        <.stat_card
          label={"Total cost (#{@period})"}
          value={"$#{Decimal.round(@total_cost, 2)}"}
        />
        <.stat_card
          label={"Energy used (#{@period})"}
          value={Decimal.round(@total_kwh, 1) |> to_string()}
          unit="kWh"
        />
        <.stat_card
          label="Active suggestions"
          value={length(@suggestions) |> to_string()}
        />
      </div>

      <%# Chart %>
      <div class="bg-white rounded-xl p-6 shadow-sm border border-gray-100">
        <h2 class="text-sm font-semibold text-gray-700 mb-4">Energy cost over time</h2>
        <canvas
          id="energy-chart"
          phx-hook="EnergyChart"
          data-chart={Jason.encode!(@chart_data)}
          class="w-full h-64"
        />
      </div>

      <%# Suggestions %>
      <div :if={@suggestions != []}>
        <h2 class="text-lg font-semibold text-gray-900 mb-3">💡 Smart suggestions</h2>
        <div class="space-y-3">
          <.suggestion_card :for={s <- @suggestions} suggestion={s} />
        </div>
      </div>

      <%# Empty state %>
      <div :if={@summaries == [] and @suggestions == []} class="text-center py-16 text-gray-400">
        <p class="text-4xl mb-4">📊</p>
        <p class="font-medium text-gray-600">No data yet</p>
        <p class="text-sm mt-1">
          <.link href={~p"/setup"} class="text-green-600 hover:underline">Set up your devices</.link>
          then <.link href={~p"/logs"} class="text-green-600 hover:underline">log your first usage</.link>.
        </p>
      </div>
    </div>
    """
  end
end
