defmodule Pulse.Footprint.Observation do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "footprint_observations" do
    belongs_to :user, Pulse.Accounts.User
    field :external_id, :string
    field :scope, :string
    field :starts_on, :date
    field :ends_on, :date
    field :quantity, :float
    field :unit, :string
    field :basis, :string, default: "source"
    field :factor_kwh_per_unit, :float
    field :coverage, :float, default: 1.0
    field :allocation, :float, default: 1.0
    field :household, :boolean, default: false
    field :included_in_scope, :string
    field :source_ref, :string
    field :quality, :string, default: "estimated"
    field :payload, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :external_id,
      :scope,
      :starts_on,
      :ends_on,
      :quantity,
      :unit,
      :basis,
      :factor_kwh_per_unit,
      :coverage,
      :allocation,
      :household,
      :included_in_scope,
      :source_ref,
      :quality,
      :payload
    ])
    |> validate_required([
      :external_id,
      :scope,
      :starts_on,
      :ends_on,
      :quantity,
      :unit,
      :basis,
      :coverage,
      :allocation,
      :quality
    ])
    |> validate_inclusion(:scope, Pulse.Footprint.scopes())
    |> validate_inclusion(:included_in_scope, Pulse.Footprint.scopes())
    |> validate_inclusion(:unit, ~w(kwh km liter therm meal usd night item hour request))
    |> validate_inclusion(:basis, ~w(source electricity gas fuel))
    |> validate_inclusion(:quality, ~w(measured estimated))
    |> validate_length(:external_id, min: 1, max: 200)
    |> validate_length(:source_ref, max: 2000)
    |> validate_number(:quantity,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000
    )
    |> validate_number(:factor_kwh_per_unit,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000
    )
    |> validate_number(:coverage, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:allocation, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_dates()
    |> validate_factor()
    |> unique_constraint([:user_id, :external_id])
  end

  defp validate_dates(cs) do
    first = get_field(cs, :starts_on)
    last = get_field(cs, :ends_on)

    if first && last &&
         (Date.compare(first, ~D[2020-01-01]) == :lt or Date.compare(last, first) == :lt or
            Date.diff(last, first) > 3660),
       do:
         add_error(
           cs,
           :ends_on,
           "must follow the start date and span at most ten years, starting in 2020 or later"
         ),
       else: cs
  end

  defp validate_factor(cs) do
    scope = get_field(cs, :scope)
    unit = get_field(cs, :unit)
    factor = get_field(cs, :factor_kwh_per_unit)

    built_in =
      unit == "kwh" or (scope == "ground_travel" and unit in ~w(km liter)) or
        (scope == "home_heating" and unit == "therm") or (scope == "food" and unit == "meal")

    cs =
      if not built_in and is_nil(factor),
        do: add_error(cs, :factor_kwh_per_unit, "is required for this unit"),
        else: cs

    cs = if not is_nil(factor), do: validate_required(cs, [:source_ref]), else: cs

    if get_field(cs, :included_in_scope) == scope && not is_nil(scope),
      do: add_error(cs, :included_in_scope, "must be a different category"),
      else: cs
  end
end
