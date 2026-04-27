defmodule PulseWeb.UserRegistrationLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts
  alias Pulse.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})
    {:ok, assign(socket, form: to_form(changeset), page_title: "Create account")}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/confirm-email/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(:info, "Account created! Check your email to confirm.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-gray-900">⚡ Pulse</h1>
          <p class="text-gray-500 mt-2">Create your account</p>
        </div>

        <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
          <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:password]} type="password" label="Password (12+ characters)" required />
            <.button type="submit" variant={:primary} class="w-full">Create account</.button>
          </.form>
        </div>

        <div class="text-center mt-4 text-sm text-gray-500">
          Already have an account?
          <.link href={~p"/login"} class="text-green-600 hover:underline">Sign in</.link>
        </div>
      </div>
    </div>
    """
  end
end
