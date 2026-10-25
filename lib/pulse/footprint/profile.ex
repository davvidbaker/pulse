defmodule Pulse.Footprint.Profile do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "footprint_profiles" do
    belongs_to :user, Pulse.Accounts.User
    field :household_size, :float, default: 2.5
    field :grid_source_factor, :float, default: 2.8
    field :heating, :string, default: "unknown"
    field :drives, :boolean, default: true
    field :daily_travel_km, :float
    field :vehicle_kwh_per_km, :float
    field :vehicle_id, :string
    field :vehicle_energy_basis, :string, default: "fuel"
    field :baselines, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(profile, attrs) do
    attrs =
      case attrs["baselines"] do
        values when is_map(values) ->
          parsed =
            for {key, value} <- values, value not in ["", nil], into: %{} do
              number =
                case value do
                  v when is_binary(v) ->
                    case Float.parse(v) do
                      {n, ""} -> n
                      _ -> v
                    end

                  v ->
                    v
                end

              {key, number}
            end

          Map.put(attrs, "baselines", parsed)

        _ ->
          attrs
      end

    profile
    |> cast(attrs, [
      :household_size,
      :grid_source_factor,
      :heating,
      :drives,
      :daily_travel_km,
      :vehicle_kwh_per_km,
      :vehicle_id,
      :vehicle_energy_basis,
      :baselines
    ])
    |> validate_required([:household_size, :grid_source_factor, :heating, :drives])
    |> validate_number(:household_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_number(:grid_source_factor,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> validate_number(:daily_travel_km, greater_than_or_equal_to: 0, less_than_or_equal_to: 5000)
    |> validate_number(:vehicle_kwh_per_km,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_inclusion(:heating, ~w(unknown gas electric none))
    |> validate_inclusion(:vehicle_energy_basis, ~w(fuel electricity source))
    |> validate_format(:vehicle_id, ~r/^\d{1,8}$/)
    |> validate_change(:baselines, fn :baselines, baselines ->
      if Enum.all?(baselines, fn {k, v} ->
           k in Pulse.Footprint.scopes() and is_number(v) and v >= 0 and v <= 1_000_000
         end),
         do: [],
         else: [baselines: "must map categories to non-negative source kWh/day"]
    end)
    |> unique_constraint(:user_id)
  end
end
