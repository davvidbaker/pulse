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
end
