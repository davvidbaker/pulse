defmodule Pulse.Suggestions.Suggestion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @suggestion_types ~w(time_shift reduce_duration upgrade_device)

  schema "suggestions" do
    field(:suggestion_type, :string)
    field(:title, :string)
    field(:body, :string)
    field(:estimated_saving_weekly, :decimal)
    field(:generated_at, :utc_datetime)
    field(:dismissed_at, :utc_datetime)
    field(:acted_on_at, :utc_datetime)

    belongs_to(:user, Pulse.Accounts.User)
    belongs_to(:energy_source, Pulse.Setup.EnergySource)

    timestamps(type: :utc_datetime)
  end

  def changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [
      :suggestion_type,
      :title,
      :body,
      :estimated_saving_weekly,
      :generated_at,
      :dismissed_at,
      :acted_on_at,
      :user_id,
      :energy_source_id
    ])
    |> validate_required([:suggestion_type, :title, :body, :user_id, :energy_source_id])
    |> validate_inclusion(:suggestion_type, @suggestion_types)
  end
end
