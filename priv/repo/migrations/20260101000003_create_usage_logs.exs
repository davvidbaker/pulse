defmodule Pulse.Repo.Migrations.CreateUsageLogs do
  use Ecto.Migration

  def change do
    create table(:usage_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :energy_source_id, references(:energy_sources, type: :binary_id, on_delete: :nilify_all)

      add :logged_at, :utc_datetime, null: false
      add :duration_minutes, :integer
      add :quantity, :decimal
      add :input_type, :string, null: false
      add :notes, :string

      # Computed async by CalculationWorker
      add :computed_kwh, :decimal
      add :computed_cost, :decimal
      add :computed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:usage_logs, [:user_id])
    create index(:usage_logs, [:user_id, :logged_at])
    create index(:usage_logs, [:energy_source_id])
    create index(:usage_logs, [:user_id, :computed_at])
  end
end
