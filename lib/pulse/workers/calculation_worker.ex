defmodule Pulse.Workers.CalculationWorker do
  @moduledoc """
  Oban worker that calculates energy usage and cost for a UsageLog.
  Runs in the :calculations queue. After success, triggers:
  - Summary rebuild for the log's date
  - Notification rule checks
  - Badge evaluation
  - Suggestion generation (debounced: only if last generated > 6h ago)
  - PubSub broadcast to update the LiveView row
  """

  use Oban.Worker, queue: :calculations, max_attempts: 3

  alias Pulse.{Logs, Summaries, Notifications, Gamification, Suggestions}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"log_id" => log_id}}) do
    case Logs.recalculate_log(log_id) do
      {:ok, log} ->
        date = DateTime.to_date(log.logged_at)

        Summaries.rebuild_daily_summary(log.user_id, date)
        Notifications.check_rules_for_user(log.user_id)
        Gamification.check_and_award_badges(log.user_id)
        maybe_generate_suggestions(log.user_id)

        Phoenix.PubSub.broadcast(
          Pulse.PubSub,
          "user:#{log.user_id}:log_computed",
          {:log_computed, log.id}
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_generate_suggestions(user_id) do
    # Only regenerate if no suggestion was generated in the last 6 hours
    six_hours_ago = DateTime.add(DateTime.utc_now(), -6 * 3600, :second)

    recent_suggestion =
      Pulse.Suggestions.Suggestion
      |> Ecto.Query.where(
        [s],
        s.user_id == ^user_id and s.generated_at >= ^six_hours_ago
      )
      |> Ecto.Query.limit(1)
      |> Pulse.Repo.one()

    unless recent_suggestion do
      Suggestions.generate_suggestions(user_id)
    end
  end
end
