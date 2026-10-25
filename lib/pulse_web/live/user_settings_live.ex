defmodule PulseWeb.UserSettingsLive do
  use PulseWeb, :live_view

  alias Pulse.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Account settings")
      |> assign(:email_available, Pulse.Mailer.delivery_available?())
      |> assign(:email_form, to_form(Accounts.change_user_email(user)))
      |> assign(:password_form, to_form(Accounts.change_user_password(user)))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"token" => token}, _url, socket) do
    message =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok -> {:info, "Email updated successfully."}
        :error -> {:error, "Email change link is invalid or has expired."}
      end

    {kind, text} = message
    {:noreply, socket |> put_flash(kind, text) |> redirect(to: ~p"/users/settings")}
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_email", %{"user" => params}, socket) do
    changeset = Accounts.change_user_email(socket.assigns.current_user, params)
    {:noreply, assign(socket, :email_form, to_form(changeset, action: :validate))}
  end

  def handle_event("update_email", _params, %{assigns: %{email_available: false}} = socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Email changes are unavailable while email delivery is not configured."
     )}
  end

  def handle_event("update_email", %{"user" => params}, socket) do
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, params["current_password"], params) do
      {:ok, applied_user} ->
        delivery =
          Accounts.deliver_user_update_email_instructions(
            applied_user,
            user.email,
            &url(~p"/users/settings/confirm-email/#{&1}")
          )

        case delivery do
          {:ok, _} ->
            {:noreply,
             put_flash(socket, :info, "Check your new email for confirmation instructions.")}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "We could not send the confirmation email. Your email address has not changed; try again later."
             )}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(changeset))}
    end
  end

  def handle_event("validate_password", %{"user" => params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.current_user, params)
    {:noreply, assign(socket, :password_form, to_form(changeset, action: :validate))}
  end

  def handle_event("update_password", %{"user" => params}, socket) do
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, params["current_password"], params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated. Please sign in again.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md space-y-8">
      <h1 class="text-2xl font-bold text-gray-900">Account settings</h1>

      <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <h2 class="font-semibold text-gray-900 mb-4">Change email</h2>
        <p :if={!@email_available} class="mb-4 text-sm text-amber-900">
          Email changes are unavailable while email delivery is not configured.
        </p>
        <.form
          for={@email_form}
          phx-change="validate_email"
          phx-submit="update_email"
          class="space-y-4"
        >
          <.input field={@email_form[:email]} type="email" label="New email" required />
          <.input
            field={@email_form[:current_password]}
            type="password"
            label="Current password"
            required
          />
          <.button type="submit" variant={:primary} disabled={!@email_available}>
            Update email
          </.button>
        </.form>
      </div>

      <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <h2 class="font-semibold text-gray-900 mb-4">Change password</h2>
        <.form
          for={@password_form}
          phx-change="validate_password"
          phx-submit="update_password"
          class="space-y-4"
        >
          <.input
            field={@password_form[:current_password]}
            type="password"
            label="Current password"
            required
          />
          <.input field={@password_form[:password]} type="password" label="New password" required />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            required
          />
          <.button type="submit" variant={:primary}>Update password</.button>
        </.form>
      </div>
    </div>
    """
  end
end
