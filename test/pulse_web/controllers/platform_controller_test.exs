defmodule PulseWeb.PlatformControllerTest do
  use PulseWeb.ConnCase
  import Pulse.Factory
  @token String.duplicate("test-secret-", 4)

  setup do
    user = insert(:user, timezone: "America/Denver")
    Application.put_env(:pulse, :platform_token, @token)
    Application.put_env(:pulse, :platform_user_id, user.id)

    on_exit(fn ->
      Application.delete_env(:pulse, :platform_token)
      Application.delete_env(:pulse, :platform_user_id)
    end)

    %{user: user}
  end

  test "service endpoints require a token even with a browser session", %{conn: conn, user: user} do
    conn = conn |> log_in_user(user) |> get("/api/platform/inputs/2026-10-24")
    assert json_response(conn, 401)["error"] == "unauthorized"
  end

  test "inputs are scoped to the configured user and local day", %{conn: conn, user: user} do
    other = insert(:user)

    attrs = %{
      "external_id" => "entry",
      "scope" => "food",
      "starts_on" => "2026-10-24",
      "ends_on" => "2026-10-24",
      "quantity" => 3,
      "unit" => "meal"
    }

    assert {:ok, _} = Pulse.Footprint.put_observation(other.id, attrs)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get("/api/platform/inputs/2026-10-24?user_id=#{other.id}")

    data = json_response(conn, 200)
    assert data["timezone"] == user.timezone
    assert data["observations"] == []
    assert is_binary(data["input_hash"])
  end

  test "invalid dates are rejected", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get("/api/platform/inputs/not-a-date")

    assert json_response(conn, 422)["error"] == "invalid_date"
  end
end
