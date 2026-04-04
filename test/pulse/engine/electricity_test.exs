defmodule Pulse.Engine.ElectricityTest do
  use ExUnit.Case, async: true

  alias Pulse.Engine.Electricity

  @metadata %{
    "tariff_kwh" => 0.15,
    "rated_kw" => 2.0
  }

  describe "calculate/2" do
    test "calculates kwh and cost for a 60-minute session" do
      input = %{duration_minutes: 60, logged_at: nil}

      assert {:ok, result} = Electricity.calculate(input, @metadata)
      # 60min / 60 * 2kW = 2.0 kWh
      assert Decimal.equal?(result.kwh, Decimal.from_float(2.0))
      # 2.0 kWh * $0.15 = $0.30
      assert Decimal.equal?(result.cost, Decimal.from_float(0.3))
    end

    test "calculates correctly for 30-minute session" do
      input = %{duration_minutes: 30, logged_at: nil}

      assert {:ok, result} = Electricity.calculate(input, @metadata)
      assert Decimal.equal?(result.kwh, Decimal.from_float(1.0))
      assert Decimal.equal?(result.cost, Decimal.from_float(0.15))
    end

    test "returns error when duration is missing" do
      assert {:error, _} = Electricity.calculate(%{duration_minutes: 0, logged_at: nil}, @metadata)
    end

    test "returns error when metadata is incomplete" do
      assert {:error, _} = Electricity.calculate(%{duration_minutes: 60, logged_at: nil}, %{})
    end

    test "applies peak hour multiplier" do
      metadata =
        Map.put(@metadata, "peak_hours", [
          %{"from" => "07:00", "to" => "23:00", "multiplier" => 2.0}
        ])

      # 10:00 is in peak
      logged_at = ~U[2026-01-01 10:00:00Z]
      input = %{duration_minutes: 60, logged_at: logged_at}

      assert {:ok, result} = Electricity.calculate(input, metadata)
      # 2.0 kWh * $0.15 * 2.0 multiplier = $0.60
      assert Decimal.equal?(result.cost, Decimal.from_float(0.6))
    end

    test "no multiplier applied outside peak hours" do
      metadata =
        Map.put(@metadata, "peak_hours", [
          %{"from" => "07:00", "to" => "23:00", "multiplier" => 2.0}
        ])

      # 03:00 is off-peak
      logged_at = ~U[2026-01-01 03:00:00Z]
      input = %{duration_minutes: 60, logged_at: logged_at}

      assert {:ok, result} = Electricity.calculate(input, metadata)
      assert Decimal.equal?(result.cost, Decimal.from_float(0.3))
    end
  end
end
