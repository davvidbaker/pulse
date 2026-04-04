defmodule Pulse.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notification_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :energy_source_id, references(:energy_sources, type: :binary_id, on_delete: :nilify_all)
      add :rule_type, :string, null: false
      add :threshold_value, :decimal, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notification_rules, [:user_id])

    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :notification_rule_id,
          references(:notification_rules, type: :binary_id, on_delete: :nilify_all)
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :string
      add :read_at, :utc_datetime
      add :payload, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:user_id, :read_at])
  end
end
