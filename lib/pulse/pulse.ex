defmodule Pulse.Pulse do
  @moduledoc """
  Computes the user's daily Pulse metric.

  Pulse is an estimated personal marginal emissions rate expressed as
  kg CO2e per kWh, derived from the user's computed logs and source mix.
  """

  import Ecto.Query

  alias Pulse.Logs.UsageLog
  alias Pulse.Repo

  @default_factors %{
    "electricity" => 0.42,
    "gas" => 0.20,
    "heating" => 0.19,
    "water" => 0.0
  }

  @fuel_factors %{
    "petrol" => 0.27,
    "diesel" => 0.29,
    "hybrid" => 0.22,
    "electric" => 0.08
  }

  @spec daily(binary(), Date.t()) :: %{
          pulse_rate: Decimal.t() | nil,
          emissions_kg: Decimal.t(),
          total_kwh: Decimal.t(),
          logs_count: non_neg_integer()
        }
  def daily(user_id, date \\ Date.utc_today()) do
    {from_dt, to_dt} = day_bounds(date)

    logs =
      UsageLog
      |> where(
        [l],
        l.user_id == ^user_id and
          l.logged_at >= ^from_dt and
          l.logged_at < ^to_dt and
          not is_nil(l.computed_kwh)
      )
      |> preload(:energy_source)
      |> Repo.all()

    emissions_kg =
      Enum.reduce(logs, Decimal.new(0), fn log, acc ->
        Decimal.add(acc, estimate_log_emissions(log))
      end)

    total_kwh =
      Enum.reduce(logs, Decimal.new(0), fn log, acc ->
        Decimal.add(acc, log.computed_kwh || Decimal.new(0))
      end)

    pulse_rate =
      if Decimal.gt?(total_kwh, 0) do
        Decimal.div(emissions_kg, total_kwh)
      end

    %{
      pulse_rate: pulse_rate,
      emissions_kg: emissions_kg,
      total_kwh: total_kwh,
      logs_count: length(logs)
    }
  end

  defp day_bounds(date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    {start_dt, end_dt}
  end

  defp estimate_log_emissions(%{computed_kwh: nil}), do: Decimal.new(0)

  defp estimate_log_emissions(log) do
    factor = emission_factor(log.energy_source)
    Decimal.mult(log.computed_kwh, Decimal.from_float(factor))
  end

  defp emission_factor(nil), do: 0.0

  defp emission_factor(%{metadata: metadata} = source) do
    metadata = metadata || %{}

    metadata["marginal_emission_rate"] ||
      case source.source_type do
        "fuel" -> Map.get(@fuel_factors, metadata["fuel_type"], 0.27)
        type -> Map.get(@default_factors, type, 0.30)
      end
      |> normalize_factor()
  end

  defp normalize_factor(val) when is_float(val), do: val
  defp normalize_factor(val) when is_integer(val), do: val * 1.0

  defp normalize_factor(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp normalize_factor(_), do: 0.0
end
