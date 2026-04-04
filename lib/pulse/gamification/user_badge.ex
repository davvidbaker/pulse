defmodule Pulse.Gamification.UserBadge do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_badges" do
    field :awarded_at, :utc_datetime

    belongs_to :user, Pulse.Accounts.User
    belongs_to :badge, Pulse.Gamification.Badge

    timestamps(type: :utc_datetime)
  end

  def changeset(user_badge, attrs) do
    user_badge
    |> cast(attrs, [:user_id, :badge_id, :awarded_at])
    |> validate_required([:user_id, :badge_id, :awarded_at])
    |> unique_constraint([:user_id, :badge_id])
  end
end
