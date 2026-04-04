defmodule Pulse.Summaries do
  @moduledoc """
  The Summaries context. Owns DailySummary.
  Aggregates daily costs from UsageLog and serves dashboard data.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Summaries.DailySummary
  alias Pulse.Logs.UsageLog

  @spec rebuild_daily_summary(binary(), Date.t()) :: {:ok, DailySummary.t()} | {:error, term()}
  def rebuild_daily_summary(user_id, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    logs =
      UsageLog
      |> where(
        [l],
        l.user_id == ^user_id and
          l.logged_at >= ^start_dt and
          l.logged_at < ^end_dt and
          not is_nil(l.computed_cost)
      )
      |> Repo.all()

    total_kwh =
      Enum.reduce(logs, Decimal.new(0), fn l, acc ->
        Decimal.add(acc, l.computed_kwh || Decimal.new(0))
      end)

    total_cost =
      Enum.reduce(logs, Decimal.new(0), fn l, acc ->
        Decimal.add(acc, l.computed_cost || Decimal.new(0))
      end)

    breakdown =
      Enum.group_by(logs, & &1.energy_source_id)
      |> Enum.map(fn {source_id, source_logs} ->
        kwh =
          Enum.reduce(source_logs, Decimal.new(0), fn l, acc ->
            Decimal.add(acc, l.computed_kwh || Decimal.new(0))
          end)

        cost =
          Enum.reduce(source_logs, Decimal.new(0), fn l, acc ->
            Decimal.add(acc, l.computed_cost || Decimal.new(0))
          end)

        {source_id, %{"kwh" => Decimal.to_float(kwh), "cost" => Decimal.to_float(cost)}}
      end)
      |> Map.new()

    attrs = %{
      user_id: user_id,
      date: date,
      total_kwh: total_kwh,
      total_cost: total_cost,
      breakdown: breakdown
    }

    case Repo.get_by(DailySummary, user_id: user_id, date: date) do
      nil ->
        %DailySummary{}
        |> DailySummary.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> DailySummary.changeset(attrs)
        |> Repo.update()
    end
  end

  @spec get_daily_summary(binary(), Date.t()) :: DailySummary.t() | nil
  def get_daily_summary(user_id, date) do
    Repo.get_by(DailySummary, user_id: user_id, date: date)
  end

  @spec list_summaries(binary(), Date.t(), Date.t()) :: [DailySummary.t()]
  def list_summaries(user_id, from_date, to_date) do
    DailySummary
    |> where([s], s.user_id == ^user_id and s.date >= ^from_date and s.date <= ^to_date)
    |> order_by([s], asc: s.date)
    |> Repo.all()
  end

  @spec weekly_total(binary(), Date.t()) :: %{total_cost: Decimal.t(), total_kwh: Decimal.t()}
  def weekly_total(user_id, reference_date \\ Date.utc_today()) do
    week_start = Date.add(reference_date, -Date.day_of_week(reference_date) + 1)
    week_end = Date.add(week_start, 6)
    aggregate_range(user_id, week_start, week_end)
  end

  @spec monthly_total(binary(), Date.t()) :: %{total_cost: Decimal.t(), total_kwh: Decimal.t()}
  def monthly_total(user_id, reference_date \\ Date.utc_today()) do
    month_start = Date.beginning_of_month(reference_date)
    month_end = Date.end_of_month(reference_date)
    aggregate_range(user_id, month_start, month_end)
  end

  @spec comparison_with_average(binary(), Date.t()) :: %{
          user_weekly_cost: Decimal.t(),
          avg_weekly_cost: Decimal.t(),
          percentile: float()
        }
  def comparison_with_average(user_id, reference_date \\ Date.utc_today()) do
    week_start = Date.add(reference_date, -Date.day_of_week(reference_date) + 1)
    week_end = Date.add(week_start, 6)

    user_total = aggregate_range(user_id, week_start, week_end)

    avg_result =
      DailySummary
      |> where([s], s.date >= ^week_start and s.date <= ^week_end)
      |> select([s], %{avg_cost: avg(s.total_cost)})
      |> Repo.one()

    # Compute approximate percentile: what fraction of users spent more than current user
    user_cost = user_total.total_cost

    below_user_count =
      DailySummary
      |> where([s], s.date >= ^week_start and s.date <= ^week_end)
      |> group_by([s], s.user_id)
      |> having([s], sum(s.total_cost) < ^user_cost)
      |> select([s], s.user_id)
      |> Repo.aggregate(:count)

    total_users =
      DailySummary
      |> where([s], s.date >= ^week_start and s.date <= ^week_end)
      |> select([s], s.user_id)
      |> distinct(true)
      |> Repo.aggregate(:count)

    percentile =
      if total_users > 0, do: below_user_count / total_users * 100.0, else: 50.0

    %{
      user_weekly_cost: user_cost,
      avg_weekly_cost: avg_result[:avg_cost] || Decimal.new(0),
      percentile: Float.round(percentile, 1)
    }
  end

  @spec aggregate_range(binary(), Date.t(), Date.t()) :: %{total_cost: Decimal.t(), total_kwh: Decimal.t()}
  def aggregate_range(user_id, from_date, to_date) do
    result =
      DailySummary
      |> where([s], s.user_id == ^user_id and s.date >= ^from_date and s.date <= ^to_date)
      |> select([s], %{total_cost: sum(s.total_cost), total_kwh: sum(s.total_kwh)})
      |> Repo.one()

    %{
      total_cost: result[:total_cost] || Decimal.new(0),
      total_kwh: result[:total_kwh] || Decimal.new(0)
    }
  end
end
