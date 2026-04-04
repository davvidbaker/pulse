defmodule Pulse.Engine do
  @moduledoc """
  The calculation engine. Stateless — no database access.
  Dispatches to sub-modules based on energy source type.

  All public functions return `{:ok, result_map}` or `{:error, reason}`.
  """

  alias Pulse.Engine.{Electricity, Fuel, Gas, Water}

  @type log_input :: %{
          optional(:duration_minutes) => pos_integer(),
          optional(:quantity) => number(),
          optional(:logged_at) => DateTime.t(),
          optional(:input_type) => String.t()
        }

  @type calculation_result :: %{
          kwh: Decimal.t(),
          cost: Decimal.t()
        }

  @doc """
  Calculate energy consumption and cost for a given log input and energy source.

  ## Parameters
  - `log_input` - map with `:duration_minutes` and/or `:quantity`, plus `:logged_at`
  - `energy_source` - `%EnergySource{}` struct or compatible map with `:source_type` and `:metadata`
  """
  @spec calculate(log_input(), map()) :: {:ok, calculation_result()} | {:error, String.t()}
  def calculate(log_input, %{source_type: "electricity", metadata: metadata}) do
    Electricity.calculate(log_input, metadata)
  end

  def calculate(log_input, %{source_type: "gas", metadata: metadata}) do
    Gas.calculate(log_input, metadata)
  end

  def calculate(log_input, %{source_type: "fuel", metadata: metadata}) do
    Fuel.calculate(log_input, metadata)
  end

  def calculate(log_input, %{source_type: "water", metadata: metadata}) do
    Water.calculate(log_input, metadata)
  end

  def calculate(log_input, %{source_type: "heating", metadata: metadata}) do
    # Heating is modeled as gas-like: duration * rated output, using a boiler efficiency factor
    efficiency = parse_float(metadata["boiler_efficiency"]) || 0.9
    adjusted_kw = (parse_float(metadata["rated_output_kw"]) || 0) * efficiency

    adjusted_metadata =
      metadata
      |> Map.put("rated_output_kw", adjusted_kw)
      |> Map.put_new("cost_per_cubic_meter", metadata["cost_per_cubic_meter"] || 0)

    Gas.calculate(log_input, adjusted_metadata)
  end

  def calculate(_, %{source_type: type}) do
    {:error, "unknown source_type: #{type}"}
  end

  @doc """
  Estimate daily usage projection based on a list of recent log results.
  Returns the average daily cost and kwh over the provided logs.
  """
  @spec estimate_daily([map()], pos_integer()) :: %{
          avg_daily_cost: Decimal.t(),
          avg_daily_kwh: Decimal.t()
        }
  def estimate_daily(computed_logs, days \\ 14) when length(computed_logs) > 0 do
    total_cost =
      Enum.reduce(computed_logs, Decimal.new(0), fn log, acc ->
        Decimal.add(acc, log.computed_cost || Decimal.new(0))
      end)

    total_kwh =
      Enum.reduce(computed_logs, Decimal.new(0), fn log, acc ->
        Decimal.add(acc, log.computed_kwh || Decimal.new(0))
      end)

    days_dec = Decimal.new(days)

    %{
      avg_daily_cost: Decimal.div(total_cost, days_dec),
      avg_daily_kwh: Decimal.div(total_kwh, days_dec)
    }
  end

  def estimate_daily([], _), do: %{avg_daily_cost: Decimal.new(0), avg_daily_kwh: Decimal.new(0)}

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0
  defp parse_float(_), do: nil
end
