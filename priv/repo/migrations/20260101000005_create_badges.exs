defmodule Pulse.Repo.Migrations.CreateBadges do
  use Ecto.Migration

  def change do
    create table(:badges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :icon, :string
      add :criteria, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:badges, [:key])

    create table(:user_badges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :badge_id, references(:badges, type: :binary_id, on_delete: :delete_all), null: false
      add :awarded_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_badges, [:user_id, :badge_id])
    create index(:user_badges, [:user_id])
  end
end
