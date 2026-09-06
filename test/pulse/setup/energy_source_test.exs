defmodule Pulse.Setup.EnergySourceTest do
  use ExUnit.Case, async: true

  alias Pulse.Setup.EnergySource

  describe "changeset/3" do
    test "accepts numeric metadata submitted as strings from the form" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "name" => "Home Electricity",
        "source_type" => "electricity",
        "metadata" => %{
          "tariff_kwh" => "0.15",
          "rated_kw" => "2.5"
        }
      }

      changeset = EnergySource.changeset(%EnergySource{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :unit) == "kwh"

      assert Ecto.Changeset.get_change(changeset, :metadata) == %{
               "tariff_kwh" => 0.15,
               "rated_kw" => 2.5
             }
    end

    test "still rejects non-numeric metadata values" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "name" => "Home Electricity",
        "source_type" => "electricity",
        "metadata" => %{
          "tariff_kwh" => "abc",
          "rated_kw" => "2.5"
        }
      }

      changeset = EnergySource.changeset(%EnergySource{}, attrs)

      refute changeset.valid?
      assert {"tariff_kwh must be a positive number", _opts} = changeset.errors[:metadata]
    end
  end
end
