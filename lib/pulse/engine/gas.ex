defmodule Pulse.Engine.Gas do
  @moduledoc """
  Calculates gas usage and cost for boiler/heating sources.

  Formula:
    kwh = (duration_minutes / 60) * rated_output_kw
    kwh_per_m3 = calorific_value_mj_per_m3 / 3.6
    cubic_meters = kwh / kwh_per_m3
    cost = cubic_meters * cost_per_cubic_meter

  Calorific value for natural gas is typically ~38.5 MJ/m³.
  """

  @spec calculate(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def calculate(%{duration_minutes: duration}, metadata)
      when is_integer(duration) and duration > 0 do
    rated_output_kw = parse_float(metadata["rated_output_kw"])
    calorific_value = parse_float(metadata["calorific_value"]) || 38.5
    cost_per_m3 = parse_float(metadata["cost_per_cubic_meter"])

    if is_nil(rated_output_kw) or is_nil(cost_per_m3) do
      {:error, "gas source missing rated_output_kw or cost_per_cubic_meter"}
    else
      kwh = duration / 60.0 * rated_output_kw
      kwh_per_m3 = calorific_value / 3.6
      cubic_meters = kwh / kwh_per_m3
      cost = cubic_meters * cost_per_m3

      {:ok,
       %{
         kwh: Decimal.from_float(Float.round(kwh, 6)),
         cost: Decimal.from_float(Float.round(cost, 6)),
         cubic_meters: Decimal.from_float(Float.round(cubic_meters, 6))
       }}
    end
  end

  def calculate(_, _), do: {:error, "gas requires duration_minutes > 0"}

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
