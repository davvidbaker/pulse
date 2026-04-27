alias Pulse.Repo
alias Pulse.Gamification.Badge

# Seed badges
badges = [
  %{
    key: "first_log",
    name: "First step",
    description: "Logged your first energy usage.",
    icon: "🌱",
    criteria: %{type: "log_count", count: 1}
  },
  %{
    key: "ten_logs",
    name: "Getting started",
    description: "Logged 10 usages.",
    icon: "📊",
    criteria: %{type: "log_count", count: 10}
  },
  %{
    key: "hundred_logs",
    name: "Power tracker",
    description: "Logged 100 usages — you really know your consumption!",
    icon: "⚡",
    criteria: %{type: "log_count", count: 100}
  },
  %{
    key: "streak_7",
    name: "Week streak",
    description: "Logged usage for 7 consecutive days.",
    icon: "🔥",
    criteria: %{type: "streak", days: 7}
  },
  %{
    key: "streak_30",
    name: "Month streak",
    description: "Logged usage for 30 consecutive days.",
    icon: "🏆",
    criteria: %{type: "streak", days: 30}
  },
  %{
    key: "under_budget_week",
    name: "Savings mode",
    description: "Spent 20% less than your 4-week average this week.",
    icon: "💰",
    criteria: %{type: "under_budget", period: "week", pct: 20}
  },
  %{
    key: "top_25_percent",
    name: "Eco champion",
    description: "Your weekly energy cost is in the bottom 25% of all users.",
    icon: "🌍",
    criteria: %{type: "social_compare", percentile: 25}
  }
]

Enum.each(badges, fn attrs ->
  case Repo.get_by(Badge, key: attrs.key) do
    nil ->
      Repo.insert!(Badge.changeset(%Badge{}, attrs))
      IO.puts("Seeded badge: #{attrs.key}")

    _existing ->
      IO.puts("Badge already exists: #{attrs.key}")
  end
end)

IO.puts("Seeds complete.")
