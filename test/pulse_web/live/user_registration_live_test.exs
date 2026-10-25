defmodule PulseWeb.UserRegistrationLiveTest do
  use PulseWeb.ConnCase, async: false

  test "registration remains usable when email is not configured", %{conn: conn} do
    previous = Application.fetch_env!(:pulse, Pulse.Mailer)
    Application.put_env(:pulse, Pulse.Mailer, adapter: Pulse.Mailer.Unconfigured)
    on_exit(fn -> Application.put_env(:pulse, Pulse.Mailer, previous) end)

    {:ok, view, _html} = live(conn, ~p"/register")

    view
    |> form("form", user: %{email: "new@example.com", password: "a long test password"})
    |> render_submit()

    assert_redirect(view, ~p"/login")

    assert Pulse.Accounts.get_user_by_email_and_password(
             "new@example.com",
             "a long test password"
           )
  end
end
