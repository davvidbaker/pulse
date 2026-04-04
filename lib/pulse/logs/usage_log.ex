defmodule Pulse.Logs.UsageLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @input_types ~w(duration quantity)

  schema "usage_logs" do
    field :logged_at, :utc_datetime
    field :duration_minutes, :integer
    field :quantity, :decimal
    field :input_type, :string
    field :notes, :string

    # Computed async by CalculationWorker
    field :computed_kwh, :decimal
    field :computed_cost, :decimal
    field :computed_at, :utc_datetime

    belongs_to :user, Pulse.Accounts.User
    belongs_to :energy_source, Pulse.Setup.EnergySource

    timestamps(type: :utc_datetime)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :logged_at,
      :duration_minutes,
      :quantity,
      :input_type,
      :notes,
      :user_id,
      :energy_source_id
    ])
    |> validate_required([:logged_at, :input_type, :user_id, :energy_source_id])
    |> validate_inclusion(:input_type, @input_types)
    |> validate_input_presence()
  end

  def computed_changeset(log, %{kwh: kwh, cost: cost}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    log
    |> change(%{
      computed_kwh: kwh,
      computed_cost: cost,
      computed_at: now
    })
  end

  defp validate_input_presence(changeset) do
    input_type = get_field(changeset, :input_type)

    case input_type do
      "duration" ->
        changeset
        |> validate_required([:duration_minutes])
        |> validate_number(:duration_minutes, greater_than: 0)

      "quantity" ->
        changeset
        |> validate_required([:quantity])
        |> validate_number(:quantity, greater_than: 0)

      _ ->
        changeset
    end
  end
end
