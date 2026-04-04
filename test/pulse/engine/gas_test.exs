defmodule Pulse.Engine.GasTest do
  use ExUnit.Case, async: true

  alias Pulse.Engine.Gas

  @metadata %{
    "rated_output_kw" => 24.0,
    "calorific_value" => 38.5,
    "cost_per_cubic_meter" => 0.08
  }

  describe "calculate/2" do
    test "calculates cubic meters and cost for a 60-minute session" do
      input = %{duration_minutes: 60}

      assert {:ok, result} = Gas.calculate(input, @metadata)
      # kwh = 60/60 * 24 = 24 kWh
      # kwh_per_m3 = 38.5 / 3.6 ≈ 10.694
      # cubic_meters = 24 / 10.694 ≈ 2.245
      # cost = 2.245 * 0.08 ≈ 0.1796
      assert Decimal.gt?(result.cost, Decimal.new(0))
      assert Decimal.gt?(result.cubic_meters, Decimal.new(0))
      assert Decimal.gt?(result.kwh, Decimal.new(0))
    end

    test "returns error when duration is zero or negative" do
      assert {:error, _} = Gas.calculate(%{duration_minutes: 0}, @metadata)
    end

    test "returns error when metadata is missing rated_output_kw" do
      assert {:error, _} = Gas.calculate(%{duration_minutes: 60}, %{"cost_per_cubic_meter" => 0.08})
    end
  end
end
