defmodule PulseWeb.DashboardLive do
  use PulseWeb, :live_view
  import PulseWeb.FootprintComponents

  alias Pulse.{Footprint, Notifications, Suggestions, Summaries}
  alias Pulse.Footprint.PeriodSummary

  @periods [:day, :week, :month]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elixir.Pulse.PubSub, "user:#{user.id}:log_computed")
      Phoenix.PubSub.subscribe(Elixir.Pulse.PubSub, "user:#{user.id}:notifications")
      Process.send_after(self(), :refresh_footprint, 60_000)
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:period, :day)
      |> assign(:unread_count, Notifications.unread_count(user.id))
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    period = Enum.find(@periods, &(to_string(&1) == period))

    if period in @periods do
      {:noreply, socket |> assign(:period, period) |> select_period()}
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

  def handle_info(:refresh_footprint, socket) do
    Process.send_after(self(), :refresh_footprint, 60_000)
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    user = socket.assigns.current_user
    today = Footprint.local_today(user)
    {week_start, _} = PeriodSummary.bounds(today, :week)
    first = Enum.min([week_start, Date.beginning_of_month(today)], Date)

    socket
    |> assign(:today, today)
    |> assign(:footprint_results, Footprint.results_in_range(user.id, first, today))
    |> assign(:usage_summaries, Summaries.list_summaries(user.id, first, today))
    |> assign(:suggestions, Suggestions.list_active_suggestions(user.id))
    |> select_period()
  end

  defp select_period(socket) do
    {first, last} = PeriodSummary.bounds(socket.assigns.today, socket.assigns.period)

    summary =
      PeriodSummary.new(
        socket.assigns.footprint_results,
        socket.assigns.period,
        first,
        last,
        socket.assigns.current_user.timezone
      )

    summaries =
      Enum.filter(
        socket.assigns.usage_summaries,
        &(Date.compare(&1.date, first) != :lt and Date.compare(&1.date, last) != :gt)
      )

    total_cost =
      Enum.reduce(summaries, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_cost) end)

    total_kwh =
      Enum.reduce(summaries, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_kwh) end)

    chart_data = %{
      labels: Enum.map(summary.points, &Date.to_iso8601(&1.date)),
      watts: Enum.map(summary.points, & &1.watts)
    }

    socket
    |> assign(:summaries, summaries)
    |> assign(:summary, summary)
    |> assign(:total_cost, total_cost)
    |> assign(:total_kwh, total_kwh)
    |> assign(:chart_data, chart_data)
    |> push_event("pulse_chart_updated", %{data: chart_data})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <.pulse_hero summary={@summary}>
        <:controls>
          <button
            :for={p <- [:day, :week, :month]}
            phx-click="change_period"
            phx-value-period={p}
            aria-pressed={to_string(@period == p)}
            class={[
              "px-3 py-1.5 rounded-lg text-sm font-medium transition",
              @period == p && "bg-green-600 text-white",
              @period != p && "bg-white border border-gray-300 text-gray-600 hover:bg-gray-50"
            ]}
          >
            {String.capitalize(to_string(p))}
          </button>
        </:controls>
      </.pulse_hero>

      <section class="bg-white rounded-xl p-6 shadow-sm border border-gray-100">
        <h2 class="text-sm font-semibold text-gray-700">Daily average power</h2>
        <p class="text-sm text-slate-500 mt-1 mb-4">
          Watts for each local day in the selected period. Gaps mean no calculation is available.
        </p>
        <div
          id="pulse-chart"
          phx-hook="PulseChart"
          phx-update="ignore"
          data-chart={Jason.encode!(@chart_data)}
          class="w-full min-w-0"
        />
        <details class="mt-3 text-sm text-slate-600">
          <summary class="cursor-pointer">Daily values</summary>
          <ul class="mt-2 space-y-1">
            <li :for={point <- @summary.points}>
              {point.date}: {if is_nil(point.watts),
                do: "Not calculated",
                else: "#{point.watts} watts"}
            </li>
          </ul>
        </details>
      </section>

      <details class="rounded-xl border border-gray-100 bg-white p-6 space-y-4">
        <summary class="cursor-pointer text-sm font-semibold text-gray-700">
          Logged utility usage and costs
        </summary>
        <p class="text-sm text-slate-500">
          These totals cover your usage logs for the selected period. They use delivered energy, separate from the source-energy Pulse estimate above.
        </p>
        <div :if={@summaries != []} class="grid grid-cols-2 gap-4">
          <.stat_card label="Logged cost" value={"$#{Decimal.round(@total_cost, 2)}"} />
          <.stat_card
            label="Logged energy"
            value={Decimal.round(@total_kwh, 1) |> to_string()}
            unit="kWh"
          />
        </div>
        <p :if={@summaries == []} class="text-sm text-slate-600">
          No utility usage logged for this period. <.link
            href={~p"/logs"}
            class="text-green-700 underline"
          >Add a usage log</.link>.
        </p>
      </details>

      <%!-- Suggestions --%>
      <div :if={@suggestions != []}>
        <h2 class="text-lg font-semibold text-gray-900 mb-3">💡 Smart suggestions</h2>
        <div class="space-y-3">
          <.suggestion_card :for={s <- @suggestions} suggestion={s} />
        </div>
      </div>
    </div>
    """
  end
end
