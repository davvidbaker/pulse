defmodule Pulse.Workers.NotificationWorker do
  @moduledoc """
  Oban cron worker for sending scheduled notifications (e.g., weekly summaries).
  Runs every Monday at 08:00 UTC.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query
  alias Pulse.{Repo, Summaries, Notifications}
  alias Pulse.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "weekly_summary"}}) do
    today = Date.utc_today()
    week_start = Date.add(today, -7)
    week_end = Date.add(today, -1)

    User
    |> select([u], u.id)
    |> Repo.all()
    |> Enum.each(fn user_id ->
      send_weekly_summary(user_id, week_start, week_end)
    end)

    :ok
  end

  def perform(_), do: :ok

  defp send_weekly_summary(user_id, week_start, week_end) do
    %{total_cost: cost, total_kwh: kwh} = Summaries.aggregate_range(user_id, week_start, week_end)

    Notifications.create_notification(user_id, %{
      type: "weekly_summary",
      title: "Your weekly energy report",
      body:
        "Last week you used #{Decimal.round(kwh, 1)} kWh and spent $#{Decimal.round(cost, 2)}.",
      payload: %{
        week_start: Date.to_iso8601(week_start),
        week_end: Date.to_iso8601(week_end),
        total_cost: Decimal.to_float(cost),
        total_kwh: Decimal.to_float(kwh)
      }
    })
  end
end
