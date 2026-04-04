defmodule Pulse.Summaries.DailySummary do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "daily_summaries" do
    field(:date, :date)
    field(:total_kwh, :decimal, default: Decimal.new(0))
    field(:total_cost, :decimal, default: Decimal.new(0))
    # %{source_id => %{kwh: float, cost: float}}
    field(:breakdown, :map, default: %{})

    belongs_to(:user, Pulse.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [:date, :total_kwh, :total_cost, :breakdown, :user_id])
    |> validate_required([:date, :user_id])
    |> unique_constraint([:user_id, :date])
  end
end
