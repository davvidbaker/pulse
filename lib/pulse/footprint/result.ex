defmodule Pulse.Footprint.Result do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "footprint_results" do
    belongs_to :user, Pulse.Accounts.User
    field :date, :date
    field :input_hash, :string
    field :methodology_version, :string
    field :revision, :integer, default: 1
    field :calculated_at, :utc_datetime_usec
    field :dirty, :boolean, default: false
    field :data, :map
    field :receipts, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
