defmodule PulseWeb.UserSessionController do
  use PulseWeb, :controller

  alias Pulse.Accounts
  alias PulseWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}, info)
       when is_binary(email) and is_binary(password) do
    if Pulse.Accounts.AuthLimiter.allow?(:login, email) do
      authenticate(conn, user_params, info)
    else
      conn
      |> put_flash(:error, "Too many sign-in attempts. Please try again in five minutes.")
      |> redirect(to: ~p"/login")
    end
  end

  defp create(conn, _params, _info) do
    conn |> put_flash(:error, "Invalid email or password") |> redirect(to: ~p"/login")
  end

  defp authenticate(conn, %{"email" => email, "password" => password} = user_params, info) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
