defmodule Pulse.Repo.Migrations.CreateFootprintPlatform do
  use Ecto.Migration

  def change do
    create table(:footprint_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :household_size, :float, null: false, default: 2.5
      add :grid_source_factor, :float, null: false, default: 2.8
      add :heating, :string, null: false, default: "unknown"
      add :drives, :boolean, null: false, default: true
      add :daily_travel_km, :float
      add :vehicle_kwh_per_km, :float
      add :vehicle_id, :string
      add :vehicle_energy_basis, :string, null: false, default: "fuel"
      add :baselines, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:footprint_profiles, [:user_id])

    create table(:footprint_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :scope, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :quantity, :float, null: false
      add :unit, :string, null: false
      add :basis, :string, null: false, default: "source"
      add :factor_kwh_per_unit, :float
      add :coverage, :float, null: false, default: 1.0
      add :allocation, :float, null: false, default: 1.0
      add :household, :boolean, null: false, default: false
      add :included_in_scope, :string
      add :source_ref, :text
      add :quality, :string, null: false, default: "estimated"
      add :payload, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:footprint_observations, [:user_id, :external_id])
    create index(:footprint_observations, [:user_id, :starts_on, :ends_on])

    create table(:footprint_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :input_hash, :string, null: false
      add :methodology_version, :string, null: false
      add :revision, :integer, null: false, default: 1
      add :calculated_at, :utc_datetime_usec, null: false
      add :dirty, :boolean, null: false, default: false
      add :data, :map, null: false
      add :receipts, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:footprint_results, [:user_id, :date])
  end
end
