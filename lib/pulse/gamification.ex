defmodule Pulse.Gamification do
  @moduledoc """
  The Gamification context. Owns Badge and UserBadge.
  Evaluates badge criteria and awards badges to users.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Gamification.{Badge, UserBadge}
  alias Pulse.Logs.UsageLog
  alias Pulse.Summaries.DailySummary

  @spec list_user_badges(binary()) :: [UserBadge.t()]
  def list_user_badges(user_id) do
    UserBadge
    |> where([ub], ub.user_id == ^user_id)
    |> preload(:badge)
    |> order_by([ub], desc: ub.awarded_at)
    |> Repo.all()
  end

  @spec list_all_badges() :: [Badge.t()]
  def list_all_badges, do: Repo.all(Badge)

  @doc """
  Evaluates all unearned badges for a user and awards any that are now eligible.
  Returns the list of newly awarded UserBadge structs.
  """
  @spec check_and_award_badges(binary()) :: [UserBadge.t()]
  def check_and_award_badges(user_id) do
    earned_badge_ids =
      UserBadge
      |> where([ub], ub.user_id == ^user_id)
      |> select([ub], ub.badge_id)
      |> Repo.all()

    unearned_badges =
      Badge
      |> where([b], b.id not in ^earned_badge_ids)
      |> Repo.all()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.flat_map(unearned_badges, fn badge ->
      if criteria_met?(badge.criteria, user_id) do
        case Repo.insert(
               UserBadge.changeset(%UserBadge{}, %{
                 user_id: user_id,
                 badge_id: badge.id,
                 awarded_at: now
               }),
               on_conflict: :nothing
             ) do
          {:ok, user_badge} ->
            notify_badge_awarded(user_id, badge)
            [user_badge]

          _ ->
            []
        end
      else
        []
      end
    end)
  end

  defp criteria_met?(%{"type" => "log_count", "count" => required_count}, user_id) do
    actual_count =
      UsageLog
      |> where([l], l.user_id == ^user_id)
      |> Repo.aggregate(:count, :id)
    actual_count >= required_count
  end

  defp criteria_met?(%{"type" => "streak", "days" => required_days}, user_id) do
    recent_dates =
      DailySummary
      |> where([s], s.user_id == ^user_id and s.total_cost > 0)
      |> order_by([s], desc: s.date)
      |> limit(^required_days)
      |> select([s], s.date)
      |> Repo.all()

    has_streak?(recent_dates, required_days)
  end

  defp criteria_met?(
         %{"type" => "under_budget", "period" => "week", "pct" => pct_below},
         user_id
       ) do
    today = Date.utc_today()
    week_start = Date.add(today, -Date.day_of_week(today) + 1)
    four_weeks_ago = Date.add(week_start, -28)

    current_week_cost =
      DailySummary
      |> where([s], s.user_id == ^user_id and s.date >= ^week_start and s.date <= ^today)
      |> select([s], sum(s.total_cost))
      |> Repo.one() || Decimal.new(0)

    avg_cost =
      DailySummary
      |> where(
        [s],
        s.user_id == ^user_id and s.date >= ^four_weeks_ago and s.date < ^week_start
      )
      |> select([s], avg(s.total_cost) * 7)
      |> Repo.one() || Decimal.new(0)

    if Decimal.gt?(avg_cost, Decimal.new(0)) do
      threshold = Decimal.mult(avg_cost, Decimal.from_float(1.0 - pct_below / 100.0))
      Decimal.lt?(current_week_cost, threshold)
    else
      false
    end
  end

  defp criteria_met?(%{"type" => "social_compare", "percentile" => max_percentile}, user_id) do
    today = Date.utc_today()
    week_start = Date.add(today, -Date.day_of_week(today) + 1)

    user_cost =
      DailySummary
      |> where([s], s.user_id == ^user_id and s.date >= ^week_start and s.date <= ^today)
      |> select([s], sum(s.total_cost))
      |> Repo.one() || Decimal.new(0)

    users_with_higher_cost =
      DailySummary
      |> where([s], s.date >= ^week_start and s.date <= ^today)
      |> group_by([s], s.user_id)
      |> having([s], sum(s.total_cost) > ^user_cost)
      |> select([s], s.user_id)
      |> Repo.aggregate(:count)

    total_users =
      DailySummary
      |> where([s], s.date >= ^week_start and s.date <= ^today)
      |> select([s], s.user_id)
      |> distinct(true)
      |> Repo.aggregate(:count)

    percentile = if total_users > 0, do: users_with_higher_cost / total_users * 100.0, else: 50.0
    percentile <= max_percentile
  end

  defp criteria_met?(_, _), do: false

  defp has_streak?(dates, required_days) when length(dates) < required_days, do: false

  defp has_streak?(dates, required_days) do
    dates
    |> Enum.take(required_days)
    |> Enum.zip(0..(required_days - 1))
    |> Enum.all?(fn {date, offset} ->
      Date.compare(date, Date.add(Date.utc_today(), -offset)) == :eq
    end)
  end

  defp notify_badge_awarded(user_id, badge) do
    Pulse.Notifications.create_notification(user_id, %{
      type: "badge_awarded",
      title: "Badge unlocked: #{badge.name}",
      body: badge.description,
      payload: %{badge_key: badge.key, badge_icon: badge.icon}
    })
  end
end
