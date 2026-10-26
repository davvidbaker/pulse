defmodule Pulse.Footprint.PeriodSummary do
  @moduledoc "Read-only presentation of saved daily estimates; never fills missing days with zero."
  alias Pulse.Footprint

  defstruct [
    :period,
    :from,
    :to,
    :timezone,
    :calculated_at,
    available_days: 0,
    total_days: 0,
    hours: 0.0,
    total_kwh: 0.0,
    lower_kwh: 0.0,
    upper_kwh: 0.0,
    observed_fraction: 0.0,
    categories: %{},
    points: [],
    missing_scopes: [],
    dirty: false
  ]

  def bounds(day, :day), do: {day, day}
  def bounds(day, :week), do: {Date.add(day, 1 - Date.day_of_week(day)), day}
  def bounds(day, :month), do: {Date.beginning_of_month(day), day}

  def new(results, period, first, last, timezone) do
    results =
      Enum.filter(
        results,
        &(&1.data["timezone"] == timezone and Date.compare(&1.date, first) != :lt and
            Date.compare(&1.date, last) != :gt)
      )

    days = Enum.to_list(Date.range(first, last))
    indexed = Map.new(results, &{&1.date, &1})
    total = sum(results, "total_kwh")
    observed = Enum.sum(Enum.map(results, &(&1.data["total_kwh"] * &1.data["observed_fraction"])))

    categories =
      Map.new(Footprint.scopes(), fn scope ->
        values = Enum.map(results, & &1.data["categories"][scope])
        methods = values |> Enum.map(& &1["method"]) |> Enum.uniq()
        refs = values |> Enum.map(& &1["source_ref"]) |> Enum.filter(&is_binary/1) |> Enum.uniq()

        {scope,
         %{
           "source_kwh" => Enum.sum(Enum.map(values, & &1["source_kwh"])),
           "missing" => values == [] or Enum.any?(values, & &1["missing"]),
           "method" =>
             case methods do
               [method] -> method
               [] -> "missing"
               _ -> "mixed"
             end,
           "methods" => methods,
           "source_ref" => if(refs != [], do: Enum.join(refs, " · ")),
           "full_estimate_days" => Enum.count(values, &(!&1["missing"])),
           "day_count" => length(results),
           "factors" => []
         }}
      end)

    %__MODULE__{
      period: period,
      from: first,
      to: last,
      timezone: timezone,
      available_days: length(results),
      total_days: length(days),
      hours: Enum.sum(Enum.map(results, &hours/1)),
      total_kwh: total,
      lower_kwh: sum(results, "lower_kwh"),
      upper_kwh: sum(results, "upper_kwh"),
      observed_fraction: if(total > 0, do: observed / total, else: 0.0),
      categories: categories,
      missing_scopes: Enum.filter(Footprint.scopes(), &categories[&1]["missing"]),
      dirty: Enum.any?(results, & &1.dirty),
      calculated_at: results |> Enum.map(& &1.calculated_at) |> Enum.max(DateTime, fn -> nil end),
      points:
        Enum.map(days, fn day ->
          row = indexed[day]
          %{date: day, watts: if(row, do: round(row.data["total_kwh"] * 1000 / hours(row)))}
        end)
    }
  end

  defp sum(results, key), do: Enum.sum(Enum.map(results, & &1.data[key]))

  defp hours(row) do
    {first, last} = Footprint.day_bounds(row.date, row.data["timezone"])
    DateTime.diff(last, first, :second) / 3600
  end
end
