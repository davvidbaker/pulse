defmodule PulseWeb.UserConfirmationLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Account confirmed!")
         |> redirect(to: ~p"/dashboard")}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Confirmation link is invalid or has expired.")
         |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
