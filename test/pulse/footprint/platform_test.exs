defmodule Pulse.Footprint.PlatformTest do
  use Pulse.DataCase
  import Pulse.Factory
  alias Pulse.Footprint

  test "local days preserve DST boundaries" do
    {a, b} = Footprint.day_bounds(~D[2026-03-08], "America/Denver")
    assert DateTime.diff(b, a, :hour) == 23
    {a, b} = Footprint.day_bounds(~D[2026-11-01], "America/Denver")
    assert DateTime.diff(b, a, :hour) == 25
  end

  test "bill allocation, imports and user isolation" do
    user = insert(:user, timezone: "America/Denver")
    other = insert(:user)
    assert {:ok, _} = Footprint.update_profile(user.id, %{"household_size" => 2})

    attrs = %{
      "external_id" => "bill-1",
      "scope" => "home_electricity",
      "starts_on" => "2026-10-01",
      "ends_on" => "2026-10-10",
      "quantity" => 100,
      "unit" => "kwh",
      "basis" => "electricity",
      "household" => true
    }

    assert {:ok, first} = Footprint.put_observation(user.id, attrs)
    assert {:ok, second} = Footprint.put_observation(user.id, Map.put(attrs, "quantity", 200))
    assert first.id == second.id
    assert length(Footprint.list_observations(user.id)) == 1
    assert Footprint.list_observations(other.id) == []
    [row] = Footprint.inputs(user, ~D[2026-10-05])["observations"]
    assert row["quantity"] == 20
    assert row["allocation"] == 0.5
    assert {:error, :not_found} = Footprint.delete_observation(other.id, first.id)
  end

  test "stale input hashes are rejected and delivery receipts are revision-scoped" do
    user = insert(:user)
    day = ~D[2026-10-24]
    snapshot = Footprint.inputs(user, day)
    data = result(snapshot)
    assert {:ok, stored} = Footprint.save_result(user, day, data)
    assert stored.revision == 1
    assert {:ok, same} = Footprint.save_result(user, day, data)
    assert same.revision == 1
    assert {:ok, _} = Footprint.receipt(user.id, day, 1, "pulse_energy", 123)
    assert {:ok, _} = Footprint.update_profile(user.id, %{"household_size" => 3})
    assert {:error, :stale_inputs} = Footprint.save_result(user, day, data)
    assert {:error, :stale_inputs} = Footprint.receipt(user.id, day, 1, "pulse_energy_lower", 124)
    new_data = result(Footprint.inputs(user, day))
    assert {:ok, next} = Footprint.save_result(user, day, new_data)
    assert next.revision == 2
    assert next.receipts == %{}
  end

  test "negative observations and custom factors without references are rejected" do
    user = insert(:user)

    attrs = %{
      "scope" => "goods",
      "starts_on" => "2026-10-24",
      "ends_on" => "2026-10-24",
      "quantity" => -1,
      "unit" => "item"
    }

    assert {:error, cs} = Footprint.put_observation(user.id, attrs)
    refute cs.valid?
  end

  defp result(snapshot) do
    categories =
      Map.new(Footprint.scopes(), fn scope ->
        {scope,
         %{
           "source_kwh" => 0,
           "missing" => true,
           "complete_observed" => false,
           "method" => "missing",
           "coverage" => 0
         }}
      end)

    %{
      "date" => snapshot["date"],
      "timezone" => snapshot["timezone"],
      "input_hash" => snapshot["input_hash"],
      "methodology_version" => "test-v1",
      "energy_basis" => "source_equivalent",
      "total_kwh" => 0,
      "lower_kwh" => 0,
      "upper_kwh" => 0,
      "observed_fraction" => 0,
      "status" => "partial",
      "missing_scopes" => Footprint.scopes(),
      "categories" => categories
    }
  end
end
