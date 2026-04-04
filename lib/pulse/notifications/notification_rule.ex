defmodule Pulse.Notifications.NotificationRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rule_types ~w(threshold_daily_cost threshold_weekly_cost threshold_kwh)

  schema "notification_rules" do
    field(:rule_type, :string)
    field(:threshold_value, :decimal)
    field(:enabled, :boolean, default: true)

    belongs_to(:user, Pulse.Accounts.User)
    # nil = any source
    belongs_to(:energy_source, Pulse.Setup.EnergySource)

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:rule_type, :threshold_value, :enabled, :user_id, :energy_source_id])
    |> validate_required([:rule_type, :threshold_value, :user_id])
    |> validate_inclusion(:rule_type, @rule_types)
    |> validate_number(:threshold_value, greater_than: 0)
  end
end
