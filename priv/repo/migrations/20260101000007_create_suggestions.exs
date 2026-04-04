defmodule Pulse.Repo.Migrations.CreateSuggestions do
  use Ecto.Migration

  def change do
    create table(:suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :energy_source_id, references(:energy_sources, type: :binary_id, on_delete: :delete_all),
          null: false
      add :suggestion_type, :string, null: false
      add :title, :string, null: false
      add :body, :string, null: false
      add :estimated_saving_weekly, :decimal
      add :generated_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :acted_on_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:suggestions, [:user_id])
    create index(:suggestions, [:user_id, :dismissed_at])
    create index(:suggestions, [:user_id, :energy_source_id, :suggestion_type])
  end
end
