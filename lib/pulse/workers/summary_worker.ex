defmodule Pulse.Workers.SummaryWorker do
  @moduledoc """
  Oban worker / cron job that rebuilds daily summaries for all users.
  Scheduled to run at 00:05 UTC daily. Can also be enqueued manually
  for a specific user + date via args.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias Pulse.{Repo, Summaries}
  alias Pulse.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "date" => date_str}}) do
    date = Date.from_iso8601!(date_str)
    Summaries.rebuild_daily_summary(user_id, date)
    :ok
  end

  def perform(%Oban.Job{args: %{}}) do
    # Cron invocation: rebuild yesterday's summary for all users
    yesterday = Date.add(Date.utc_today(), -1)

    User
    |> select([u], u.id)
    |> Repo.all()
    |> Enum.each(fn user_id ->
      Summaries.rebuild_daily_summary(user_id, yesterday)
    end)

    :ok
  end
end
