defmodule Pulse.Engine.Fuel do
  @moduledoc """
  Calculates fuel usage and cost for vehicle sources.

  Formula (duration-based):
    distance_km = (duration_minutes / 60) * avg_speed_kmh  (default: 50 km/h)
    liters = distance_km * (consumption_per_100km / 100)
    cost = liters * cost_per_liter
    kwh_equivalent = liters * energy_density_kwh_per_liter
  """

  # Standard energy densities (kWh per liter)
  @energy_density %{
    "petrol" => 9.7,
    "diesel" => 10.7,
    "hybrid" => 9.7,
    "electric" => 0.0
  }

  @default_avg_speed_kmh 50.0

  @spec calculate(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def calculate(%{duration_minutes: duration}, metadata)
      when is_integer(duration) and duration > 0 do
    consumption = parse_float(metadata["consumption_per_100km"])
    cost_per_liter = parse_float(metadata["cost_per_liter"])
    fuel_type = metadata["fuel_type"] || "petrol"
    avg_speed = parse_float(metadata["avg_speed_kmh"]) || @default_avg_speed_kmh

    if is_nil(consumption) or is_nil(cost_per_liter) do
      {:error, "fuel source missing consumption_per_100km or cost_per_liter"}
    else
      distance_km = duration / 60.0 * avg_speed
      liters = distance_km * consumption / 100.0
      cost = liters * cost_per_liter
      energy_density = Map.get(@energy_density, fuel_type, 9.7)
      kwh = liters * energy_density

      {:ok,
       %{
         kwh: Decimal.from_float(Float.round(kwh, 6)),
         cost: Decimal.from_float(Float.round(cost, 6)),
         liters: Decimal.from_float(Float.round(liters, 4)),
         distance_km: Decimal.from_float(Float.round(distance_km, 2))
       }}
    end
  end

  def calculate(%{quantity: quantity}, metadata)
      when is_number(quantity) and quantity > 0 do
    cost_per_liter = parse_float(metadata["cost_per_liter"])
    fuel_type = metadata["fuel_type"] || "petrol"

    if is_nil(cost_per_liter) do
      {:error, "fuel source missing cost_per_liter"}
    else
      cost = quantity * cost_per_liter
      energy_density = Map.get(@energy_density, fuel_type, 9.7)
      kwh = quantity * energy_density

      {:ok,
       %{
         kwh: Decimal.from_float(Float.round(kwh, 6)),
         cost: Decimal.from_float(Float.round(cost, 6)),
         liters: Decimal.from_float(Float.round(quantity * 1.0, 4))
       }}
    end
  end

  def calculate(_, _), do: {:error, "fuel requires duration_minutes > 0 or quantity > 0"}

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(_), do: nil
end
