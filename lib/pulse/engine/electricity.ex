defmodule Pulse.Engine.Electricity do
  @moduledoc """
  Calculates energy usage and cost for electricity sources.

  Formula:
    kwh = (duration_minutes / 60) * rated_kw
    multiplier = peak_hour_multiplier(logged_at, peak_hours)
    cost = kwh * tariff_kwh * multiplier
  """

  @spec calculate(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def calculate(%{duration_minutes: duration, logged_at: logged_at}, metadata)
      when is_integer(duration) and duration > 0 do
    tariff = parse_float(metadata["tariff_kwh"])
    rated_kw = parse_float(metadata["rated_kw"])

    if is_nil(tariff) or is_nil(rated_kw) do
      {:error, "electricity source missing tariff_kwh or rated_kw"}
    else
      kwh = duration / 60.0 * rated_kw
      multiplier = peak_hour_multiplier(logged_at, metadata["peak_hours"])
      cost = kwh * tariff * multiplier

      {:ok,
       %{
         kwh: Decimal.from_float(Float.round(kwh, 6)),
         cost: Decimal.from_float(Float.round(cost, 6))
       }}
    end
  end

  def calculate(_, _), do: {:error, "electricity requires duration_minutes > 0"}

  @doc "Returns the tariff multiplier based on whether logged_at falls in a peak hour window."
  @spec peak_hour_multiplier(DateTime.t() | nil, list() | nil) :: float()
  def peak_hour_multiplier(nil, _), do: 1.0
  def peak_hour_multiplier(_, nil), do: 1.0
  def peak_hour_multiplier(_, []), do: 1.0

  def peak_hour_multiplier(logged_at, peak_hours) when is_list(peak_hours) do
    time = DateTime.to_time(logged_at)

    Enum.find_value(peak_hours, 1.0, fn window ->
      with {:ok, from} <- parse_time(window["from"]),
           {:ok, to} <- parse_time(window["to"]) do
        if in_time_window?(time, from, to) do
          parse_float(window["multiplier"]) || 1.0
        end
      end
    end)
  end

  defp in_time_window?(time, from, to) do
    if Time.compare(from, to) == :lt do
      # Normal window, e.g. 07:00 -> 23:00
      Time.compare(time, from) != :lt and Time.compare(time, to) == :lt
    else
      # Overnight window, e.g. 23:00 -> 07:00
      Time.compare(time, from) != :lt or Time.compare(time, to) == :lt
    end
  end

  defp parse_time(str) when is_binary(str), do: Time.from_iso8601(str <> ":00")
  defp parse_time(_), do: :error

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0
  defp parse_float(val) when is_binary(val), do: Float.parse(val) |> elem(0)
  defp parse_float(_), do: nil
end
