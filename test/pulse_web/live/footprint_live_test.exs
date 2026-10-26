defmodule PulseWeb.FootprintLiveTest do
  use PulseWeb.ConnCase
  import Pulse.Factory

  test "authenticated user can save assumptions and an observation", %{conn: conn} do
    user = insert(:user, timezone: "America/Denver")
    {:ok, view, html} = conn |> log_in_user(user) |> live(~p"/footprint")
    assert html =~ "Your energy footprint"
    assert html =~ "Waiting for the first calculation"
    assert html =~ "licensed US drivers"
    assert html =~ "334,914,895"
    assert html =~ "agent-selected vehicle proxy"
    assert has_element?(view, "button[type=submit]", "Save assumptions")
    assert has_element?(view, "button[type=submit]", "Save observation")
    assert has_element?(view, "button[aria-label=\"About Household size\"]")

    assert view
           |> element("form[phx-submit=save_profile]")
           |> render_submit(%{
             "profile" => %{
               "household_size" => "2",
               "heating" => "electric",
               "baselines" => %{"remote_compute" => "0.5"}
             }
           }) =~ "Assumptions saved"

    assert Pulse.Footprint.profile(user.id).baselines["remote_compute"] == 0.5

    assert view
           |> element("form[phx-submit=save_observation]")
           |> render_submit(%{
             "observation" => %{
               "scope" => "food",
               "starts_on" => "2026-10-24",
               "ends_on" => "2026-10-24",
               "quantity" => "3",
               "unit" => "meal",
               "basis" => "source",
               "coverage" => "1",
               "allocation" => "1",
               "quality" => "estimated"
             }
           }) =~ "Observation saved"

    assert length(Pulse.Footprint.list_observations(user.id)) == 1
  end

  test "dashboard distinguishes missing estimates from logged utility usage", %{conn: conn} do
    user = insert(:user)
    {:ok, _, html} = conn |> log_in_user(user) |> live(~p"/dashboard")
    assert html =~ "No calculated days in this period yet"
    assert html =~ "Logged utility usage and costs"
    refute html =~ "Personal marginal emissions rate"
  end
end
