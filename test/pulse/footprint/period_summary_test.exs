defmodule Pulse.Footprint.PeriodSummaryTest do
  use Pulse.DataCase
  import Pulse.Factory
  alias Pulse.Footprint.{PeriodSummary, Result}
  alias Pulse.Footprint

  def row(date, kwh, opts \\ []) do
    %Result{
      date: date,
      dirty: Keyword.get(opts, :dirty, false),
      calculated_at: ~U[2026-10-25 12:00:00.000000Z],
      data: %{
        "timezone" => Keyword.get(opts, :timezone, "America/Denver"),
        "total_kwh" => kwh,
        "lower_kwh" => kwh * 0.5,
        "upper_kwh" => kwh * 1.5,
        "observed_fraction" => Keyword.get(opts, :observed, 0.0),
        "categories" =>
          Map.new(
            Footprint.scopes(),
            &{&1, %{"source_kwh" => kwh / 8, "missing" => false, "method" => "observations"}}
          )
      }
    }
  end

  test "day, calendar week and month select different saved days; absent days stay absent" do
    rows = [row(~D[2026-10-01], 24), row(~D[2026-10-19], 48), row(~D[2026-10-25], 96)]

    summaries =
      for period <- [:day, :week, :month] do
        {first, last} = PeriodSummary.bounds(~D[2026-10-25], period)
        PeriodSummary.new(rows, period, first, last, "America/Denver")
      end

    assert Enum.map(summaries, & &1.available_days) == [1, 2, 3]
    assert Enum.map(summaries, & &1.total_days) == [1, 7, 25]
    assert Enum.map(summaries, &(&1.total_kwh * 1000 / &1.hours)) == [4000, 3000, 7000 / 3]
    week = Enum.at(summaries, 1)
    assert Enum.map(week.points, & &1.watts) == [2000, nil, nil, nil, nil, nil, 4000]
  end

  test "period weights energy by actual hours across either DST transition" do
    for {first, last, hours} <- [
          {~D[2026-03-07], ~D[2026-03-08], 47},
          {~D[2026-10-31], ~D[2026-11-01], 49}
        ] do
      summary =
        PeriodSummary.new(
          [row(first, 24, observed: 1), row(last, 48, dirty: true)],
          :week,
          first,
          last,
          "America/Denver"
        )

      assert summary.hours == hours
      assert summary.total_kwh == 72
      assert summary.observed_fraction == 1 / 3
      assert summary.dirty
    end
  end

  test "zero is a saved day, wrong timezone is unavailable and empty periods have no average" do
    rows = [row(~D[2026-10-24], 0), row(~D[2026-10-25], 50, timezone: "Etc/UTC")]
    summary = PeriodSummary.new(rows, :week, ~D[2026-10-24], ~D[2026-10-25], "America/Denver")
    assert summary.available_days == 1
    assert summary.hours == 24
    assert Enum.map(summary.points, & &1.watts) == [0, nil]
    empty = PeriodSummary.new([], :day, ~D[2026-10-25], ~D[2026-10-25], "America/Denver")
    assert empty.available_days == 0
    assert empty.calculated_at == nil
    assert empty.points == [%{date: ~D[2026-10-25], watts: nil}]
  end

  test "database selection isolates users and dates" do
    user = insert(:user, timezone: "America/Denver")
    other = insert(:user)

    for {owner, day, kwh} <- [
          {user, ~D[2026-10-25], 48},
          {other, ~D[2026-10-25], 999},
          {user, ~D[2026-09-30], 999}
        ] do
      Repo.insert!(%{
        row(day, kwh)
        | user_id: owner.id,
          input_hash: "test",
          methodology_version: "test"
      })
    end

    summary = Footprint.period_summary(user, :month, ~D[2026-10-25])
    assert summary.total_kwh == 48
    assert summary.available_days == 1
  end
end
