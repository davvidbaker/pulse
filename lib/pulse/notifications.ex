defmodule Pulse.Notifications do
  @moduledoc """
  The Notifications context. Owns NotificationRule and Notification.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Notifications.{Notification, NotificationRule}
  alias Pulse.Summaries

  @spec list_notifications(binary(), map()) :: [Notification.t()]
  def list_notifications(user_id, opts \\ %{}) do
    query =
      Notification
      |> where([n], n.user_id == ^user_id)
      |> order_by([n], desc: n.inserted_at)

    case opts do
      %{unread_only: true} -> where(query, [n], is_nil(n.read_at))
      _ -> query
    end
    |> limit(50)
    |> Repo.all()
  end

  @spec unread_count(binary()) :: non_neg_integer()
  def unread_count(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> Repo.aggregate(:count)
  end

  @spec mark_all_read(binary()) :: {non_neg_integer(), nil}
  def mark_all_read(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Notification
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: now])
  end

  @spec mark_read(binary(), binary()) :: {:ok, Notification.t()} | {:error, term()}
  def mark_read(user_id, notification_id) do
    case Repo.get_by(Notification, id: notification_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> Notification.mark_read_changeset()
        |> Repo.update()
    end
  end

  @spec create_notification(binary(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create_notification(user_id, attrs) do
    result =
      %Notification{}
      |> Notification.changeset(Map.put(attrs, :user_id, user_id))
      |> Repo.insert()

    with {:ok, notification} <- result do
      Phoenix.PubSub.broadcast(
        Pulse.PubSub,
        "user:#{user_id}:notifications",
        {:new_notification, notification}
      )
    end

    result
  end

  @spec new_rule_changeset(map()) :: Ecto.Changeset.t()
  def new_rule_changeset(attrs \\ %{}) do
    NotificationRule.changeset(%NotificationRule{}, attrs)
  end

  @spec create_rule(binary(), map()) ::
          {:ok, NotificationRule.t()} | {:error, Ecto.Changeset.t()}
  def create_rule(user_id, attrs) do
    %NotificationRule{user_id: user_id}
    |> NotificationRule.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_rules(binary()) :: [NotificationRule.t()]
  def list_rules(user_id) do
    NotificationRule
    |> where([r], r.user_id == ^user_id)
    |> preload(:energy_source)
    |> Repo.all()
  end

  @spec toggle_rule(NotificationRule.t()) ::
          {:ok, NotificationRule.t()} | {:error, Ecto.Changeset.t()}
  def toggle_rule(%NotificationRule{} = rule) do
    rule
    |> NotificationRule.changeset(%{enabled: !rule.enabled})
    |> Repo.update()
  end

  @spec delete_rule(NotificationRule.t()) ::
          {:ok, NotificationRule.t()} | {:error, Ecto.Changeset.t()}
  def delete_rule(%NotificationRule{} = rule), do: Repo.delete(rule)

  @doc "Evaluates all active rules for a user. Creates Notification rows for any violations."
  @spec check_rules_for_user(binary()) :: :ok
  def check_rules_for_user(user_id) do
    rules =
      NotificationRule
      |> where([r], r.user_id == ^user_id and r.enabled == true)
      |> Repo.all()

    Enum.each(rules, fn rule -> check_rule(rule, user_id) end)
  end

  defp check_rule(%{rule_type: "threshold_daily_cost", threshold_value: threshold}, user_id) do
    today = Date.utc_today()

    case Summaries.get_daily_summary(user_id, today) do
      %{total_cost: cost} when not is_nil(cost) ->
        if Decimal.gt?(cost, threshold) do
          create_notification(user_id, %{
            type: "threshold_exceeded",
            title: "Daily cost alert",
            body:
              "Your daily spend of #{format_cost(cost)} has exceeded your threshold of #{format_cost(threshold)}.",
            payload: %{threshold: Decimal.to_float(threshold), actual: Decimal.to_float(cost)}
          })
        end

      _ ->
        :ok
    end
  end

  defp check_rule(%{rule_type: "threshold_weekly_cost", threshold_value: threshold}, user_id) do
    %{total_cost: cost} = Summaries.weekly_total(user_id)

    if Decimal.gt?(cost, threshold) do
      create_notification(user_id, %{
        type: "threshold_exceeded",
        title: "Weekly cost alert",
        body:
          "Your weekly spend of #{format_cost(cost)} has exceeded your threshold of #{format_cost(threshold)}.",
        payload: %{threshold: Decimal.to_float(threshold), actual: Decimal.to_float(cost)}
      })
    end
  end

  defp check_rule(_, _), do: :ok

  defp format_cost(decimal), do: "$#{Decimal.round(decimal, 2)}"
end
