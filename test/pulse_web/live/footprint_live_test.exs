defmodule PulseWeb.FootprintLiveTest do
  use PulseWeb.ConnCase
  import Pulse.Factory

  test "authenticated user can save assumptions and an observation", %{conn: conn} do
    user = insert(:user, timezone: "America/Denver")
    {:ok, view, html} = conn |> log_in_user(user) |> live(~p"/footprint")
    assert html =~ "Your energy footprint"
    assert html =~ "Waiting for the first calculation"

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

  test "dashboard presents energy and keeps carbon separate", %{conn: conn} do
    user = insert(:user)
    {:ok, _, html} = conn |> log_in_user(user) |> live(~p"/dashboard")
    assert html =~ "Estimated full-day energy footprint"
    assert html =~ "Logged emissions estimate"
    refute html =~ "Personal marginal emissions rate"
  end
end
