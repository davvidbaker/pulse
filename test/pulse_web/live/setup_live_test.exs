defmodule PulseWeb.SetupLiveTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.Factory

  test "changing the type preserves the entered name", %{conn: conn} do
    user = insert(:user)
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/setup/new")

    view
    |> form("#source-form-modal form", energy_source: %{"name" => "Kitchen Heater"})
    |> render_change()

    html =
      view
      |> form("#source-form-modal form", energy_source: %{"source_type" => "heating"})
      |> render_change()

    assert html =~ ~s(value="Kitchen Heater")
    assert html =~ "Rated output (kW)"
    assert html =~ "Boiler efficiency (0–1)"
  end
end
