defmodule PulseWeb.UserLoginLive do
  use PulseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form, page_title: "Sign in"), temporary_assigns: [form: form]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-sm">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-gray-900">⚡ Pulse</h1>
          <p class="text-gray-500 mt-2">Sign in to your account</p>
        </div>

        <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
          <.form for={@form} action={~p"/login"} class="space-y-4">
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:password]} type="password" label="Password" required />
            <label class="flex items-center gap-2 text-sm text-gray-600">
              <input type="checkbox" name="user[remember_me]" />
              Keep me signed in
            </label>
            <.button type="submit" variant={:primary} class="w-full">Sign in</.button>
          </.form>
        </div>

        <div class="text-center mt-4 text-sm text-gray-500">
          Don't have an account?
          <.link href={~p"/register"} class="text-green-600 hover:underline">Sign up</.link>
        </div>
      </div>
    </div>
    """
  end
end
