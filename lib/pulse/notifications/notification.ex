defmodule Pulse.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(threshold_exceeded weekly_summary badge_awarded suggestion)

  schema "notifications" do
    field(:type, :string)
    field(:title, :string)
    field(:body, :string)
    field(:read_at, :utc_datetime)
    field(:payload, :map, default: %{})

    belongs_to(:user, Pulse.Accounts.User)
    belongs_to(:notification_rule, Pulse.Notifications.NotificationRule)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:type, :title, :body, :read_at, :payload, :user_id, :notification_rule_id])
    |> validate_required([:type, :title, :user_id])
    |> validate_inclusion(:type, @types)
  end

  def mark_read_changeset(notification) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(notification, read_at: now)
  end
end
