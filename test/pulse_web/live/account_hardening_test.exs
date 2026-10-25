defmodule PulseWeb.FailingTestMailer do
  use Swoosh.Adapter
  def deliver(_, _), do: {:error, :simulated_outage}
end

defmodule PulseWeb.AccountHardeningTest do
  use PulseWeb.ConnCase, async: false
  import Pulse.Factory
  import Pulse.DataCase, only: [errors_on: 1]
  alias Pulse.{Accounts, Repo}
  alias Pulse.Accounts.UserToken

  defp reset_token(user) do
    {token, record} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(record)
    token
  end

  test "registration displays duplicate email and password validation errors", %{conn: conn} do
    user = insert(:user)
    {:ok, view, _} = live(conn, ~p"/register")
    html = view |> form("form", user: %{email: user.email, password: "short"}) |> render_submit()
    assert html =~ "has already been taken"
    assert html =~ "should be at least 12 character(s)"
    assert has_element?(view, "input[aria-invalid=true]")
    refute html =~ "value=\"short\""
  end

  test "blank registration fields return validation errors", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/register")
    html = render_submit(view, "save", %{"user" => %{"email" => "", "password" => ""}})
    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "email normalization and byte limits keep login and registration consistent" do
    assert {:ok, user} =
             Accounts.register_user(%{
               email: " Mixed@Example.com ",
               password: "a valid test password"
             })

    assert user.email == "mixed@example.com"

    assert Accounts.get_user_by_email_and_password(" MIXED@example.COM ", "a valid test password").id ==
             user.id

    assert Accounts.get_user_by_email_and_password(user.email, String.duplicate("x", 73)) == nil
    assert Accounts.get_user_by_email_and_password(user.email, %{}) == nil
    assert Accounts.get_user_by_email_and_password(%{}, "whatever") == nil

    assert {:error, changeset} =
             Accounts.register_user(%{
               email: "other@example.com",
               password: String.duplicate("é", 40)
             })

    assert errors_on(changeset).password != []
  end

  test "malformed login payloads return generic failure instead of crashing", %{conn: conn} do
    for payload <- [%{}, %{"user" => %{}}, %{"user" => %{"email" => [], "password" => %{}}}] do
      response = post(conn, ~p"/login", payload)
      assert redirected_to(response) == ~p"/login"
      assert Phoenix.Flash.get(response.assigns.flash, :error) == "Invalid email or password"
    end
  end

  test "reset requires confirmation, is single use, and revokes sessions" do
    user = insert(:user)
    token = reset_token(user)
    session = Accounts.generate_user_session_token(user)
    Phoenix.PubSub.subscribe(Pulse.PubSub, "users_sessions:#{Base.url_encode64(session)}")
    attrs = %{"password" => "new long test password"}
    assert {:error, cs} = Accounts.reset_user_password(token, attrs)
    assert errors_on(cs).password_confirmation == ["does not match password"]
    assert Accounts.get_user_by_reset_password_token(token)

    assert {:ok, saved} =
             Accounts.reset_user_password(
               token,
               Map.put(attrs, "password_confirmation", attrs["password"])
             )

    assert Accounts.get_user_by_email_and_password(saved.email, attrs["password"])

    assert {:error, :invalid_token} =
             Accounts.reset_user_password(
               token,
               Map.put(attrs, "password_confirmation", attrs["password"])
             )

    assert Accounts.get_user_by_session_token(session) == nil
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
  end

  test "an already mounted reset form rejects a consumed token", %{conn: conn} do
    user = insert(:user)
    token = reset_token(user)
    {:ok, view, _} = live(conn, ~p"/reset-password/#{token}")

    attrs = %{
      "password" => "new long test password",
      "password_confirmation" => "new long test password"
    }

    assert {:ok, _} = Accounts.reset_user_password(token, attrs)
    view |> form("form", user: attrs) |> render_submit()
    assert_redirect(view, ~p"/reset-password")
  end

  test "an already mounted reset form rejects expiry and shows validation errors", %{conn: conn} do
    user = insert(:user)
    token = reset_token(user)
    {:ok, view, _} = live(conn, ~p"/reset-password/#{token}")

    html =
      view
      |> form("form", user: %{password: "short", password_confirmation: "different"})
      |> render_submit()

    assert html =~ "should be at least 12 character(s)"
    assert html =~ "does not match password"

    Repo.update_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]),
      set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
    )

    view
    |> form("form",
      user: %{password: "new long test password", password_confirmation: "new long test password"}
    )
    |> render_submit()

    assert_redirect(view, ~p"/reset-password")
  end

  test "current password is validated and password updates require confirmation" do
    user = insert(:user)

    attrs = %{
      "password" => "new long test password",
      "password_confirmation" => "new long test password"
    }

    assert {:error, cs} = Accounts.update_user_password(user, "wrong password", attrs)
    assert errors_on(cs).current_password == ["is not valid"]
    assert {:ok, _} = Accounts.update_user_password(user, "password123456", attrs)
    assert {:error, stale} = Accounts.update_user_password(user, "password123456", attrs)
    assert errors_on(stale).current_password == ["is not valid"]

    assert {:error, stale_email} =
             Accounts.apply_user_email(user, "password123456", %{email: "stale@example.com"})

    assert errors_on(stale_email).current_password == ["is not valid"]
  end

  test "disabled mail is explicit and does not pretend to send", %{conn: conn} do
    previous = Application.fetch_env!(:pulse, Pulse.Mailer)
    Application.put_env(:pulse, Pulse.Mailer, adapter: Pulse.Mailer.Unconfigured)
    on_exit(fn -> Application.put_env(:pulse, Pulse.Mailer, previous) end)
    user = insert(:user)

    for email <- [user.email, "unknown@example.com"] do
      {:ok, view, html} = live(conn, ~p"/reset-password")
      assert html =~ "Password reset email is unavailable"
      assert has_element?(view, "button[disabled]")
      html = render_submit(view, "send_email", %{"user" => %{"email" => email}})
      assert html =~ "Password reset email is unavailable"
    end

    assert Repo.all(UserToken.by_user_and_contexts_query(user, ["reset_password"])) == []
  end

  test "configured recovery responds identically for known and unknown addresses", %{conn: conn} do
    user = insert(:user)

    flashes =
      for email <- [user.email, "unknown@example.com"] do
        {:ok, view, _} = live(conn, ~p"/reset-password")
        view |> form("form", user: %{email: email}) |> render_submit()
        flash = assert_redirect(view, ~p"/login")
        flash
      end

    assert hd(flashes) == List.last(flashes)
  end

  test "email confirmation works when signed out", %{conn: conn} do
    user = insert(:user, confirmed_at: nil)
    {token, record} = UserToken.build_email_token(user, "confirm")
    Repo.insert!(record)
    conn = get(conn, ~p"/confirm-email/#{token}")
    assert redirected_to(conn) == ~p"/login"
    assert Accounts.get_user!(user.id).confirmed_at
  end

  test "device edit and delete reject another owner and owner cannot be reassigned", %{conn: conn} do
    user = insert(:user)
    source = insert(:energy_source)
    {:ok, view, _} = conn |> log_in_user(user) |> live(~p"/setup")
    assert render_click(view, "delete", %{"id" => source.id}) =~ "Device not found"
    assert Pulse.Setup.get_energy_source!(source.id).active
    assert render_patch(view, ~p"/setup/#{source.id}/edit") =~ "Device not found"
    refute has_element?(view, "#source-form-modal form")

    assert {:ok, own} =
             Pulse.Setup.create_energy_source(user.id, %{
               "name" => "My device",
               "source_type" => "electricity",
               "metadata" => %{"rated_kw" => 1, "tariff_kwh" => 0.15},
               "user_id" => source.user_id
             })

    assert own.user_id == user.id
    assert {:ok, updated} = Pulse.Setup.update_energy_source(own, %{"user_id" => source.user_id})
    assert updated.user_id == user.id
  end

  test "usage cannot reference another user's device" do
    user = insert(:user)
    source = insert(:energy_source)

    assert {:error, cs} =
             Pulse.Logs.log_usage(user.id, %{
               "energy_source_id" => source.id,
               "logged_at" => DateTime.utc_now(),
               "input_type" => "quantity",
               "quantity" => 1
             })

    assert errors_on(cs).energy_source_id == ["must be one of your devices"]
  end

  test "configured mail failure keeps recovery response generic", %{conn: conn} do
    previous = Application.fetch_env!(:pulse, Pulse.Mailer)
    Application.put_env(:pulse, Pulse.Mailer, adapter: PulseWeb.FailingTestMailer)
    on_exit(fn -> Application.put_env(:pulse, Pulse.Mailer, previous) end)
    user = insert(:user)

    responses =
      for email <- [user.email, "another-unknown@example.com"] do
        {:ok, view, _} = live(conn, ~p"/reset-password")
        view |> form("form", user: %{email: email}) |> render_submit()
        assert_redirect(view, ~p"/login")
      end

    assert hd(responses) == List.last(responses)
    refute hd(responses)["info"] =~ "sent"
  end

  test "email change confirmation route applies a valid token", %{conn: conn} do
    user = insert(:user)

    {:ok, changed} =
      Accounts.apply_user_email(user, "password123456", %{email: "changed@example.com"})

    {token, record} = UserToken.build_email_token(changed, "change:#{user.email}")
    Repo.insert!(record)
    response = conn |> log_in_user(user) |> get(~p"/users/settings/confirm-email/#{token}")
    assert redirected_to(response) == ~p"/users/settings"
    assert Accounts.get_user!(user.id).email == changed.email
  end

  test "sign-in throttling applies to the HTTP endpoint", %{conn: conn} do
    email = "throttle@example.com"

    for _ <- 1..10 do
      response =
        post(conn, ~p"/login", %{"user" => %{"email" => email, "password" => "wrong password"}})

      assert Phoenix.Flash.get(response.assigns.flash, :error) == "Invalid email or password"
    end

    response =
      post(conn, ~p"/login", %{"user" => %{"email" => email, "password" => "wrong password"}})

    assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "Too many sign-in attempts"
  end
end
