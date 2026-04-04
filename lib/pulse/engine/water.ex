defmodule Pulse.Engine.Water do
  @moduledoc """
  Calculates water usage and cost.
  Water is quantity-based (cubic meters), not duration-based.

  Formula:
    cost = quantity_m3 * cost_per_cubic_meter
  """

  @spec calculate(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def calculate(%{quantity: quantity}, metadata) when is_number(quantity) and quantity > 0 do
    cost_per_m3 = parse_float(metadata["cost_per_cubic_meter"])

    if is_nil(cost_per_m3) do
      {:error, "water source missing cost_per_cubic_meter"}
    else
      cost = quantity * cost_per_m3

      {:ok,
       %{
         kwh: Decimal.new(0),
         cost: Decimal.from_float(Float.round(cost, 6)),
         cubic_meters: Decimal.from_float(Float.round(quantity * 1.0, 4))
       }}
    end
  end

  def calculate(_, _), do: {:error, "water requires quantity (cubic meters) > 0"}

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
