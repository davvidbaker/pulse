defmodule PulseWeb.UserResetPasswordLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Reset password")
      |> assign_reset_password_token(token)

    {:ok, socket}
  end

  defp assign_reset_password_token(socket, token) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      form = to_form(Accounts.change_user_password(user), as: "user")
      assign(socket, form: form, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset link is invalid or has expired.")
      |> redirect(to: ~p"/login")
    end
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully. Please log in.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <h1 class="text-2xl font-bold text-gray-900 text-center mb-6">Set new password</h1>
        <.form for={@form} phx-submit="save" class="space-y-4 bg-white rounded-xl shadow-sm border border-gray-200 p-6">
          <.input field={@form[:password]} type="password" label="New password" required />
          <.input field={@form[:password_confirmation]} type="password" label="Confirm password" required />
          <.button type="submit" variant={:primary} class="w-full">Reset password</.button>
        </.form>
      </div>
    </div>
    """
  end
end
