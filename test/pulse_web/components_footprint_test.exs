defmodule PulseWeb.FootprintComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Pulse.Footprint.Result
  alias PulseWeb.FootprintComponents

  test "average power uses the full local day, including both DST transitions" do
    for {day, hours} <- [{~D[2026-10-24], 24}, {~D[2026-03-08], 23}, {~D[2026-11-01], 25}] do
      categories =
        Map.new(
          Pulse.Footprint.scopes(),
          &{&1, %{"source_kwh" => 0, "missing" => true, "method" => "missing"}}
        )

      result = %Result{
        date: day,
        calculated_at: ~U[2026-10-25 12:00:00.000000Z],
        data: %{
          "timezone" => "America/Denver",
          "total_kwh" => hours * 2,
          "lower_kwh" => hours,
          "upper_kwh" => hours * 3,
          "observed_fraction" => 0,
          "status" => "partial",
          "categories" => categories
        }
      }

      html = render_component(&FootprintComponents.footprint_card/1, result: result)
      assert html =~ ~s(class="pulse-score">2000</span>)
      assert html =~ "1000–3000 watts average"
      assert html =~ "#{hours}.0-hour local day"
      assert html =~ "Missing is not zero"
    end
  end

  test "ring shares use category energy and unknown categories receive no invented wedge" do
    categories =
      Map.new(
        Pulse.Footprint.scopes(),
        &{&1, %{"source_kwh" => 0, "missing" => true, "method" => "missing"}}
      )

    categories =
      categories
      |> Map.put("home_electricity", %{
        "source_kwh" => 18,
        "missing" => false,
        "method" => "observations"
      })
      |> Map.put("food", %{"source_kwh" => 6, "missing" => true, "method" => "observations"})

    summary =
      Pulse.Footprint.PeriodSummary.new(
        [
          %Result{
            date: ~D[2026-10-25],
            calculated_at: ~U[2026-10-25 12:00:00.000000Z],
            data: %{
              "timezone" => "Etc/UTC",
              "categories" => categories,
              "total_kwh" => 24,
              "lower_kwh" => 12,
              "upper_kwh" => 36,
              "observed_fraction" => 0
            }
          }
        ],
        :day,
        ~D[2026-10-25],
        ~D[2026-10-25],
        "Etc/UTC"
      )

    html = render_component(&FootprintComponents.pulse_hero/1, summary: summary)
    doc = Floki.parse_fragment!(html)
    assert length(Floki.find(doc, ".pulse-ring-segment")) == 2
    assert html =~ "Home electricity: 75.0% of accounted energy"
    assert html =~ "Food: 25.0% of accounted energy; full category unknown"
    assert html =~ "Unknown energy has no slice"
    assert html =~ "Unknown"
    assert html =~ "partial"

    zero_categories =
      Map.new(categories, fn {scope, data} -> {scope, Map.put(data, "source_kwh", 0)} end)

    zero = %{summary | total_kwh: 0, categories: zero_categories}

    zero_doc =
      render_component(&FootprintComponents.pulse_hero/1, summary: zero)
      |> Floki.parse_fragment!()

    assert Floki.find(zero_doc, ".pulse-ring-segment") == []
    assert zero_doc |> Floki.find("#pulse-hero-score") |> Floki.text() == "0"
  end
end
