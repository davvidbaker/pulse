defmodule PulseWeb.BadgesLive do
  use PulseWeb, :live_view

  alias Pulse.Gamification

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_badges = Gamification.list_user_badges(user.id)
    all_badges = Gamification.list_all_badges()

    earned_ids = MapSet.new(user_badges, & &1.badge_id)

    {:ok,
     socket
     |> assign(:page_title, "Badges")
     |> assign(:user_badges, user_badges)
     |> assign(:all_badges, all_badges)
     |> assign(:earned_ids, earned_ids)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">Badges</h1>
        <p class="text-gray-500 text-sm mt-1">
          <%= MapSet.size(@earned_ids) %> / <%= length(@all_badges) %> earned
        </p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
        <div :for={badge <- @all_badges}
             class={[
               "bg-white rounded-xl p-5 text-center shadow-sm border",
               MapSet.member?(@earned_ids, badge.id) && "border-yellow-300 bg-yellow-50",
               not MapSet.member?(@earned_ids, badge.id) && "border-gray-100 opacity-50 grayscale"
             ]}>
          <p class="text-4xl mb-2"><%= badge.icon || "🏅" %></p>
          <p class="font-semibold text-gray-900 text-sm"><%= badge.name %></p>
          <p class="text-xs text-gray-500 mt-1"><%= badge.description %></p>
          <%= if MapSet.member?(@earned_ids, badge.id) do %>
            <% user_badge = Enum.find(@user_badges, &(&1.badge_id == badge.id)) %>
            <p class="text-xs text-yellow-600 mt-2 font-medium">
              Earned <%= Calendar.strftime(user_badge.awarded_at, "%b %d") %>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
