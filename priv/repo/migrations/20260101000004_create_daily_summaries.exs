defmodule Pulse.Repo.Migrations.CreateDailySummaries do
  use Ecto.Migration

  def change do
    create table(:daily_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :total_kwh, :decimal, default: 0
      add :total_cost, :decimal, default: 0
      add :breakdown, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_summaries, [:user_id, :date])
    create index(:daily_summaries, [:user_id, :date])
  end
end
