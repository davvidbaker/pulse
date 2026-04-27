defmodule PulseWeb.NotificationsLive do
  use PulseWeb, :live_view

  alias Pulse.Notifications

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    Notifications.mark_all_read(user.id)
    notifications = Notifications.list_notifications(user.id)

    Phoenix.PubSub.broadcast(
      Pulse.PubSub,
      "user:#{user.id}:notifications",
      {:notifications_read}
    )

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign(:notifications, notifications)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-2xl font-bold text-gray-900">Notifications</h1>

      <div :if={@notifications == []} class="text-center py-12 text-gray-400">
        <p class="text-3xl mb-2">🔔</p>
        <p class="text-sm">No notifications yet.</p>
      </div>

      <div class="space-y-2">
        <div :for={n <- @notifications}
             class="bg-white rounded-lg border border-gray-100 p-4 shadow-sm">
          <div class="flex justify-between items-start">
            <div>
              <p class="font-medium text-gray-900 text-sm"><%= n.title %></p>
              <p class="text-gray-600 text-sm mt-0.5"><%= n.body %></p>
            </div>
            <span class={[
              "text-xs px-2 py-0.5 rounded-full",
              n.type == "badge_awarded" && "bg-yellow-100 text-yellow-700",
              n.type == "threshold_exceeded" && "bg-red-100 text-red-700",
              n.type == "weekly_summary" && "bg-blue-100 text-blue-700",
              n.type == "suggestion" && "bg-green-100 text-green-700"
            ]}>
              <%= n.type |> String.replace("_", " ") |> String.capitalize() %>
            </span>
          </div>
          <p class="text-xs text-gray-400 mt-2">
            <%= Calendar.strftime(n.inserted_at, "%b %d, %Y at %H:%M") %>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
