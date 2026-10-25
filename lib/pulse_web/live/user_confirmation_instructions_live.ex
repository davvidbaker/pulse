defmodule PulseWeb.UserConfirmationInstructionsLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(%{}, as: "user"),
       page_title: "Resend confirmation",
       email_available: Pulse.Mailer.delivery_available?()
     )}
  end

  @impl true
  def handle_event("send_instructions", _params, %{assigns: %{email_available: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "Confirmation email is unavailable. You can still sign in.")}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
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
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/confirm-email/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "If that email is registered and unconfirmed, check your inbox. If nothing arrives, try again later."
     )
     |> redirect(to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <h1 class="text-2xl font-bold text-gray-900 text-center mb-6">Resend confirmation</h1>
        <p :if={!@email_available} class="mb-4 text-sm text-amber-900">
          Confirmation email is unavailable. You can still sign in.
        </p>
        <.form
          for={@form}
          phx-submit="send_instructions"
          class="space-y-4 bg-white rounded-xl shadow-sm border border-gray-200 p-6"
        >
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button disabled={!@email_available} type="submit" variant={:primary} class="w-full">
            Send instructions
          </.button>
        </.form>
      </div>
    </div>
    """
  end
end
