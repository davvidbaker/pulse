defmodule Pulse.Setup.EnergySource do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(electricity gas fuel water heating)
  @units %{
    "electricity" => "kwh",
    "gas" => "cubic_meters",
    "fuel" => "liters",
    "water" => "cubic_meters",
    "heating" => "kwh"
  }

  schema "energy_sources" do
    field :source_type, :string
    field :name, :string
    field :unit, :string
    field :metadata, :map, default: %{}
    field :active, :boolean, default: true

    belongs_to :user, Pulse.Accounts.User
    has_many :usage_logs, Pulse.Logs.UsageLog
    has_many :suggestions, Pulse.Suggestions.Suggestion

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an energy source.
  The `metadata` map is validated based on `source_type`.
  """
  def changeset(energy_source, attrs) do
    energy_source
    |> cast(attrs, [:source_type, :name, :unit, :metadata, :active, :user_id])
    |> validate_required([:source_type, :name, :user_id])
    |> validate_inclusion(:source_type, @source_types,
      message: "must be one of: #{Enum.join(@source_types, ", ")}"
    )
    |> set_default_unit()
    |> validate_metadata()
  end

  defp set_default_unit(changeset) do
    source_type = get_field(changeset, :source_type)

    if source_type && !get_field(changeset, :unit) do
      put_change(changeset, :unit, @units[source_type])
    else
      changeset
    end
  end

  defp validate_metadata(changeset) do
    source_type = get_field(changeset, :source_type)
    metadata = get_field(changeset, :metadata) || %{}

    if changeset.valid? && source_type do
      case validate_metadata_for_type(source_type, metadata) do
        :ok -> changeset
        {:error, reason} -> add_error(changeset, :metadata, reason)
      end
    else
      changeset
    end
  end

  defp validate_metadata_for_type("electricity", metadata) do
    required = ["tariff_kwh", "rated_kw"]

    case check_required_keys(metadata, required) do
      :ok ->
        with :ok <- validate_positive_float(metadata, "tariff_kwh"),
             :ok <- validate_positive_float(metadata, "rated_kw") do
          :ok
        end

      error ->
        error
    end
  end

  defp validate_metadata_for_type("gas", metadata) do
    required = ["cost_per_cubic_meter", "rated_output_kw", "calorific_value"]

    case check_required_keys(metadata, required) do
      :ok ->
        with :ok <- validate_positive_float(metadata, "cost_per_cubic_meter"),
             :ok <- validate_positive_float(metadata, "rated_output_kw"),
             :ok <- validate_positive_float(metadata, "calorific_value") do
          :ok
        end

      error ->
        error
    end
  end

  defp validate_metadata_for_type("fuel", metadata) do
    required = ["consumption_per_100km", "cost_per_liter", "fuel_type"]

    case check_required_keys(metadata, required) do
      :ok ->
        valid_fuel_types = ["petrol", "diesel", "hybrid", "electric"]

        if metadata["fuel_type"] in valid_fuel_types do
          with :ok <- validate_positive_float(metadata, "consumption_per_100km"),
               :ok <- validate_positive_float(metadata, "cost_per_liter") do
            :ok
          end
        else
          {:error, "fuel_type must be one of: #{Enum.join(valid_fuel_types, ", ")}"}
        end

      error ->
        error
    end
  end

  defp validate_metadata_for_type("water", metadata) do
    required = ["cost_per_cubic_meter"]

    case check_required_keys(metadata, required) do
      :ok -> validate_positive_float(metadata, "cost_per_cubic_meter")
      error -> error
    end
  end

  defp validate_metadata_for_type("heating", metadata) do
    required = ["rated_output_kw", "boiler_efficiency"]

    case check_required_keys(metadata, required) do
      :ok ->
        with :ok <- validate_positive_float(metadata, "rated_output_kw"),
             :ok <- validate_positive_float(metadata, "boiler_efficiency") do
          :ok
        end

      error ->
        error
    end
  end

  defp validate_metadata_for_type(_type, _metadata), do: :ok

  defp check_required_keys(metadata, required_keys) do
    missing = Enum.reject(required_keys, &Map.has_key?(metadata, &1))

    if missing == [] do
      :ok
    else
      {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_positive_float(metadata, key) do
    value = metadata[key]

    cond do
      is_nil(value) -> :ok
      is_number(value) && value > 0 -> :ok
      true -> {:error, "#{key} must be a positive number"}
    end
  end
end
