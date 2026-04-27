defmodule PulseWeb.UserConfirmationInstructionsLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Resend confirmation")}
  end

  @impl true
  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/confirm-email/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, "If that email is registered and unconfirmed, instructions were sent.")
     |> redirect(to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <h1 class="text-2xl font-bold text-gray-900 text-center mb-6">Resend confirmation</h1>
        <.form for={@form} phx-submit="send_instructions" class="space-y-4 bg-white rounded-xl shadow-sm border border-gray-200 p-6">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button type="submit" variant={:primary} class="w-full">Send instructions</.button>
        </.form>
      </div>
    </div>
    """
  end
end
