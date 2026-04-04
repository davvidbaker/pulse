defmodule Pulse.Repo.Migrations.CreateEnergySources do
  use Ecto.Migration

  def change do
    create table(:energy_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :name, :string, null: false
      add :unit, :string
      add :metadata, :map, default: %{}
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:energy_sources, [:user_id])
    create index(:energy_sources, [:user_id, :source_type])
  end
end
