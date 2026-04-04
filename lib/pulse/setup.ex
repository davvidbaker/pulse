defmodule Pulse.Setup do
  @moduledoc """
  The Setup context. Owns EnergySource.
  Manages the user's configured devices and their tariff/rate metadata.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Setup.EnergySource

  @spec list_energy_sources(binary()) :: [EnergySource.t()]
  def list_energy_sources(user_id) do
    EnergySource
    |> where([e], e.user_id == ^user_id and e.active == true)
    |> order_by([e], [e.source_type, e.name])
    |> Repo.all()
  end

  @spec list_all_energy_sources(binary()) :: [EnergySource.t()]
  def list_all_energy_sources(user_id) do
    EnergySource
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], [e.source_type, e.name])
    |> Repo.all()
  end

  @spec get_energy_source!(binary()) :: EnergySource.t()
  def get_energy_source!(id), do: Repo.get!(EnergySource, id)

  @spec get_energy_source(binary(), binary()) :: EnergySource.t() | nil
  def get_energy_source(user_id, id) do
    Repo.get_by(EnergySource, id: id, user_id: user_id)
  end

  @spec create_energy_source(binary(), map()) ::
          {:ok, EnergySource.t()} | {:error, Ecto.Changeset.t()}
  def create_energy_source(user_id, attrs) do
    %EnergySource{user_id: user_id}
    |> EnergySource.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_energy_source(EnergySource.t(), map()) ::
          {:ok, EnergySource.t()} | {:error, Ecto.Changeset.t()}
  def update_energy_source(%EnergySource{} = energy_source, attrs) do
    energy_source
    |> EnergySource.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_energy_source(EnergySource.t()) ::
          {:ok, EnergySource.t()} | {:error, Ecto.Changeset.t()}
  def delete_energy_source(%EnergySource{} = energy_source) do
    # Soft delete: mark inactive rather than destroy
    energy_source
    |> EnergySource.changeset(%{active: false})
    |> Repo.update()
  end

  @spec change_energy_source(EnergySource.t(), map()) :: Ecto.Changeset.t()
  def change_energy_source(%EnergySource{} = energy_source, attrs \\ %{}) do
    EnergySource.changeset(energy_source, attrs)
  end

  @doc "Returns the tariff/rate metadata for a given source, suitable for the calculation engine."
  @spec get_current_tariff(EnergySource.t()) :: map()
  def get_current_tariff(%EnergySource{metadata: metadata}), do: metadata || %{}
end
