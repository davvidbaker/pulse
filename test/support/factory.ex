defmodule Pulse.Factory do
  @moduledoc """
  ExMachina factory for tests.
  """

  use ExMachina.Ecto, repo: Pulse.Repo

  alias Pulse.Accounts.User
  alias Pulse.Setup.EnergySource
  alias Pulse.Logs.UsageLog
  alias Pulse.Summaries.DailySummary
  alias Pulse.Gamification.{Badge, UserBadge}
  alias Pulse.Notifications.{Notification, NotificationRule}
  alias Pulse.Suggestions.Suggestion

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      hashed_password: Bcrypt.hash_pwd_salt("password123456"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      timezone: "UTC"
    }
  end

  def energy_source_factory do
    %EnergySource{
      name: "Home Electricity",
      source_type: "electricity",
      unit: "kwh",
      metadata: %{
        "tariff_kwh" => 0.15,
        "rated_kw" => 2.5
      },
      active: true,
      user: build(:user)
    }
  end

  def gas_source_factory do
    %EnergySource{
      name: "Gas Boiler",
      source_type: "gas",
      unit: "cubic_meters",
      metadata: %{
        "cost_per_cubic_meter" => 0.08,
        "rated_output_kw" => 24.0,
        "calorific_value" => 38.5
      },
      active: true,
      user: build(:user)
    }
  end

  def fuel_source_factory do
    %EnergySource{
      name: "VW Golf",
      source_type: "fuel",
      unit: "liters",
      metadata: %{
        "fuel_type" => "petrol",
        "consumption_per_100km" => 7.5,
        "cost_per_liter" => 1.65,
        "avg_speed_kmh" => 50.0
      },
      active: true,
      user: build(:user)
    }
  end

  def usage_log_factory do
    %UsageLog{
      logged_at: DateTime.utc_now() |> DateTime.truncate(:second),
      duration_minutes: 60,
      input_type: "duration",
      user: build(:user),
      energy_source: build(:energy_source)
    }
  end

  def computed_usage_log_factory do
    %UsageLog{
      logged_at: DateTime.utc_now() |> DateTime.truncate(:second),
      duration_minutes: 60,
      input_type: "duration",
      computed_kwh: Decimal.new("2.5"),
      computed_cost: Decimal.new("0.375"),
      computed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      user: build(:user),
      energy_source: build(:energy_source)
    }
  end

  def daily_summary_factory do
    %DailySummary{
      date: Date.utc_today(),
      total_kwh: Decimal.new("5.0"),
      total_cost: Decimal.new("0.75"),
      breakdown: %{},
      user: build(:user)
    }
  end

  def badge_factory do
    %Badge{
      key: sequence(:badge_key, &"badge_#{&1}"),
      name: "Test Badge",
      description: "A test badge",
      icon: "🏅",
      criteria: %{"type" => "log_count", "count" => 1}
    }
  end

  def user_badge_factory do
    %UserBadge{
      awarded_at: DateTime.utc_now() |> DateTime.truncate(:second),
      user: build(:user),
      badge: build(:badge)
    }
  end

  def notification_factory do
    %Notification{
      type: "weekly_summary",
      title: "Weekly report",
      body: "Your weekly summary.",
      user: build(:user)
    }
  end

  def notification_rule_factory do
    %NotificationRule{
      rule_type: "threshold_daily_cost",
      threshold_value: Decimal.new("10.00"),
      enabled: true,
      user: build(:user)
    }
  end

  def suggestion_factory do
    %Suggestion{
      suggestion_type: "time_shift",
      title: "Save by shifting usage",
      body: "Use your device off-peak to save money.",
      estimated_saving_weekly: Decimal.new("2.50"),
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      user: build(:user),
      energy_source: build(:energy_source)
    }
  end
end
