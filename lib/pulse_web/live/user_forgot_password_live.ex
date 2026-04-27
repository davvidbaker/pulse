defmodule PulseWeb.UserForgotPasswordLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Forgot password")}
  end

  @impl true
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/reset-password/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "If that email is registered, you'll receive reset instructions shortly."
     )
     |> redirect(to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <h1 class="text-2xl font-bold text-gray-900 text-center mb-6">Reset password</h1>
        <.form for={@form} phx-submit="send_email" class="space-y-4 bg-white rounded-xl shadow-sm border border-gray-200 p-6">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button type="submit" variant={:primary} class="w-full">Send reset link</.button>
        </.form>
        <div class="text-center mt-4 text-sm">
          <.link href={~p"/login"} class="text-green-600 hover:underline">Back to login</.link>
        </div>
      </div>
    </div>
    """
  end
end
