defmodule PulseWeb.UserForgotPasswordLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(%{}, as: "user"),
       page_title: "Forgot password",
       email_available: Pulse.Mailer.delivery_available?()
     )}
  end

  @impl true
  def handle_event("send_email", _params, %{assigns: %{email_available: false}} = socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Password reset email is unavailable. Contact the app administrator for account access."
     )}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket)
      when is_binary(email) do
    if Pulse.Accounts.AuthLimiter.allow?(:recovery, email) do
      send_instructions(socket, email)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Too many recovery attempts. Please try again in fifteen minutes."
       )}
    end
  end

  defp send_instructions(socket, email) do
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
       "If that email has an account, check your inbox for reset instructions. If nothing arrives, try again later."
     )
     |> redirect(to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <h1 class="text-2xl font-bold text-gray-900 text-center mb-6">Reset password</h1>
        <p :if={!@email_available} role="status" class="mb-4 text-sm text-amber-900">
          Password reset email is unavailable. Contact the app administrator for account access.
        </p>
        <.form
          for={@form}
          phx-submit="send_email"
          class="space-y-4 bg-white rounded-xl shadow-sm border border-gray-200 p-6"
        >
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button type="submit" disabled={!@email_available} variant={:primary} class="w-full">
            Send reset link
          </.button>
        </.form>
        <div class="text-center mt-4 text-sm">
          <.link href={~p"/login"} class="text-green-600 hover:underline">Back to login</.link>
        </div>
      </div>
    </div>
    """
  end
end
