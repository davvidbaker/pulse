defmodule Pulse.Gamification.Badge do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "badges" do
    field(:key, :string)
    field(:name, :string)
    field(:description, :string)
    field(:icon, :string)
    # e.g. %{"type" => "log_count", "count" => 1}
    field(:criteria, :map, default: %{})

    has_many(:user_badges, Pulse.Gamification.UserBadge)

    timestamps(type: :utc_datetime)
  end

  def changeset(badge, attrs) do
    badge
    |> cast(attrs, [:key, :name, :description, :icon, :criteria])
    |> validate_required([:key, :name, :criteria])
    |> unique_constraint(:key)
  end
end
