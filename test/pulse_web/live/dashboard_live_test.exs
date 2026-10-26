defmodule PulseWeb.DashboardLiveTest do
  use PulseWeb.ConnCase
  import Pulse.Factory
  alias Pulse.Footprint
  alias Pulse.Repo
  alias Pulse.Footprint.{PeriodSummary, Result}

  test "period controls update the main score, dates, coverage and daily values", %{conn: conn} do
    user = insert(:user, timezone: "America/Denver")
    today = Footprint.local_today(user)
    month_start = Date.beginning_of_month(today)

    for {day, index} <- Date.range(month_start, today) |> Enum.with_index() do
      kwh = (index + 1) * 24.0

      Repo.insert!(%Result{
        user_id: user.id,
        date: day,
        input_hash: "test",
        methodology_version: "test",
        calculated_at: DateTime.utc_now(),
        data: %{
          "timezone" => user.timezone,
          "total_kwh" => kwh,
          "lower_kwh" => kwh / 2,
          "upper_kwh" => kwh * 1.5,
          "observed_fraction" => 0,
          "categories" =>
            Map.new(
              Footprint.scopes(),
              &{&1, %{"source_kwh" => kwh / 8, "missing" => false, "method" => "observations"}}
            )
        }
      })
    end

    {:ok, view, _} = conn |> log_in_user(user) |> live(~p"/dashboard")

    assert_push_event(view, "pulse_chart_updated", %{data: _initial})

    telemetry_id = {__MODULE__, make_ref()}
    owner = self()

    :telemetry.attach(
      telemetry_id,
      [:pulse, :repo, :query],
      fn _, _, _, pid -> if self() != pid, do: send(pid, :dashboard_query) end,
      owner
    )

    on_exit(fn -> :telemetry.detach(telemetry_id) end)

    for period <- [:day, :week, :month] do
      view |> element("button[phx-value-period=#{period}]") |> render_click()
      summary = Footprint.period_summary(user, period, today)
      assert has_element?(view, "#pulse-hero[data-period=#{period}]")
      assert has_element?(view, "button[phx-value-period=#{period}][aria-pressed=true]")

      assert has_element?(
               view,
               "#pulse-period-coverage",
               "Days available: #{summary.available_days} / #{summary.total_days}"
             )

      assert has_element?(
               view,
               "#pulse-period-dates",
               Calendar.strftime(summary.from, "%b %d, %Y")
             )

      # Score comes from the selected days, and the chart receives those same days.
      value = round(summary.total_kwh * 1000 / summary.hours)

      expected =
        if value >= 10000,
          do: String.replace(to_string(value), ~r/\B(?=(\d{3})+(?!\d))/, ","),
          else: to_string(value)

      assert has_element?(view, "#pulse-hero-score", expected)
      assert_push_event(view, "pulse_chart_updated", %{data: %{labels: labels, watts: watts}})
      assert labels == Enum.map(summary.points, &Date.to_iso8601(&1.date))
      assert watts == Enum.map(summary.points, & &1.watts)
      refute_received :dashboard_query
    end

    :telemetry.detach(telemetry_id)
    today_result = Footprint.result(user.id, today)

    {day_start, day_end} = Footprint.day_bounds(today, user.timezone)
    day_hours = DateTime.diff(day_end, day_start, :second) / 3600

    Repo.update!(
      Ecto.Changeset.change(today_result,
        data: Map.put(today_result.data, "total_kwh", day_hours * 100)
      )
    )

    send(view.pid, :refresh_footprint)
    render(view)
    view |> element("button[phx-value-period=day]") |> render_click()
    assert has_element?(view, "#pulse-hero-score", "100,000")
    view |> element("button[phx-value-period=month]") |> render_click()

    render_click(view, "change_period", %{"period" => "invalid-period"})
    assert has_element?(view, "#pulse-hero[data-period=month]")
  end

  test "hero groups watts only at five digits" do
    for {watts, expected} <- [{9999, "9999"}, {10000, "10,000"}] do
      summary = %PeriodSummary{
        period: :day,
        from: ~D[2026-10-25],
        to: ~D[2026-10-25],
        timezone: "Etc/UTC",
        available_days: 1,
        total_days: 1,
        total_kwh: watts * 24 / 1000,
        hours: 24.0,
        calculated_at: DateTime.utc_now(),
        categories:
          Map.new(
            Footprint.scopes(),
            &{&1, %{"source_kwh" => 0, "missing" => true, "method" => "missing"}}
          )
      }

      html = render_component(&PulseWeb.FootprintComponents.pulse_hero/1, summary: summary)

      assert html
             |> Floki.parse_fragment!()
             |> Floki.find("#pulse-hero-score")
             |> Floki.text()
             |> String.trim() == expected
    end
  end
end
