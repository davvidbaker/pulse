# CLAUDE.md — Pulse

This file provides guidance for AI assistants (Claude, etc.) working in this repository.

## Project Overview

**Pulse** is a Phoenix (Elixir) web application for tracking personal energy consumption and costs. Users configure their devices (electricity tariff, gas boiler, car, water contract), log usage in seconds ("drove 30 min", "heating on for 3h"), and the app calculates costs, provides a dashboard with charts, smart savings suggestions, notification alerts, and gamification badges.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.14+ |
| Web framework | Phoenix 1.7 + LiveView 1.0 |
| Database | PostgreSQL + Ecto 3.12 |
| Background jobs | Oban 2.18 (backed by PostgreSQL) |
| Auth | bcrypt + phx.gen.auth-style session tokens |
| Styling | Tailwind CSS 4 |
| JS build | esbuild |
| Email | Swoosh (local adapter in dev, SMTP in prod) |
| Charts | Chart.js (via CDN + LiveView JS hook) |

## Repository Structure

```
pulse/
├── config/
│   ├── config.exs          # Base config (Oban queues + cron, esbuild, tailwind)
│   ├── dev.exs             # Dev overrides (live reload, debug_errors)
│   ├── test.exs            # Test config (sandbox pool, inline Oban)
│   └── runtime.exs         # Production env vars (DATABASE_URL, SECRET_KEY_BASE, etc.)
├── lib/
│   ├── pulse/              # Domain contexts (no web concerns)
│   │   ├── accounts/       # User, UserToken, UserNotifier
│   │   ├── accounts.ex     # Registration, auth, password reset, session tokens
│   │   ├── setup/          # EnergySource schema
│   │   ├── setup.ex        # CRUD for energy sources
│   │   ├── engine/         # Pure calculation modules (no DB)
│   │   │   ├── electricity.ex
│   │   │   ├── gas.ex
│   │   │   ├── fuel.ex
│   │   │   └── water.ex
│   │   ├── engine.ex       # Dispatcher — calls sub-modules by source_type
│   │   ├── logs/           # UsageLog schema
│   │   ├── logs.ex         # log_usage/2, list_logs/2, recalculate_log/1
│   │   ├── summaries/      # DailySummary schema
│   │   ├── summaries.ex    # rebuild_daily_summary/2, weekly/monthly totals
│   │   ├── gamification/   # Badge, UserBadge schemas
│   │   ├── gamification.ex # check_and_award_badges/1, list_user_badges/1
│   │   ├── notifications/  # NotificationRule, Notification schemas
│   │   ├── notifications.ex# create_rule/2, check_rules_for_user/1
│   │   ├── suggestions/    # Suggestion schema
│   │   ├── suggestions.ex  # generate_suggestions/1, list_active_suggestions/1
│   │   ├── workers/        # Oban workers
│   │   │   ├── calculation_worker.ex   # Core pipeline: calc → summary → alerts → badges → suggestions
│   │   │   ├── summary_worker.ex       # Nightly summary rebuild (cron: 00:05 UTC)
│   │   │   ├── suggestion_worker.ex    # Nightly suggestion refresh (cron: 02:00 UTC)
│   │   │   └── notification_worker.ex  # Weekly summary emails (cron: Mon 08:00 UTC)
│   │   ├── application.ex  # OTP Application (supervisor tree)
│   │   ├── repo.ex
│   │   └── mailer.ex
│   └── pulse_web/          # Phoenix web layer
│       ├── endpoint.ex
│       ├── router.ex        # Routes: /, /login, /register, /dashboard, /setup, /logs, etc.
│       ├── user_auth.ex     # Auth plugs + on_mount hooks
│       ├── telemetry.ex
│       ├── gettext.ex
│       ├── layouts/         # root.html.heex, app.html.heex (nav + flash)
│       ├── components/
│       │   └── core_components.ex  # flash, modal, stat_card, suggestion_card, source_badge, button, input, select
│       ├── controllers/
│       │   ├── page_controller.ex         # GET / (landing page)
│       │   ├── user_session_controller.ex # POST /login, DELETE /logout
│       │   ├── error_html.ex
│       │   └── error_json.ex
│       └── live/
│           ├── dashboard_live.ex        # Charts, stats, period toggle, suggestions
│           ├── setup_live.ex            # CRUD for energy sources (modal form)
│           ├── logs_live.ex             # Quick-log form + logs list with async cost display
│           ├── notifications_live.ex    # Notification inbox
│           ├── badges_live.ex           # Badge grid (earned vs locked)
│           ├── settings_live.ex         # Timezone + notification rules
│           ├── user_login_live.ex
│           ├── user_registration_live.ex
│           ├── user_forgot_password_live.ex
│           ├── user_reset_password_live.ex
│           ├── user_settings_live.ex    # Change email / password
│           ├── user_confirmation_live.ex
│           └── user_confirmation_instructions_live.ex
├── priv/
│   ├── repo/
│   │   ├── migrations/      # 8 migration files (see below)
│   │   └── seeds.exs        # Seeds badge definitions
├── assets/
│   ├── js/app.js            # LiveSocket + EnergyChart hook (Chart.js)
│   └── css/app.css          # Tailwind CSS entry
├── test/
│   ├── support/
│   │   ├── data_case.ex     # DB sandbox base case
│   │   ├── conn_case.ex     # LiveView + controller base case
│   │   └── factory.ex       # ExMachina factories for all schemas
│   └── pulse/engine/        # Unit tests for calculation engine
├── mix.exs
├── .formatter.exs
└── .credo.exs
```

## Domain Model

### Schemas

| Schema | Table | Key fields |
|--------|-------|-----------|
| `Accounts.User` | `users` | `email`, `hashed_password`, `confirmed_at`, `timezone` |
| `Accounts.UserToken` | `users_tokens` | `token`, `context`, `sent_to` |
| `Setup.EnergySource` | `energy_sources` | `source_type` (electricity/gas/fuel/water/heating), `name`, `unit`, `metadata` (JSONB), `active` |
| `Logs.UsageLog` | `usage_logs` | `logged_at`, `duration_minutes`, `quantity`, `input_type`, `computed_kwh`, `computed_cost`, `computed_at` |
| `Summaries.DailySummary` | `daily_summaries` | `date`, `total_kwh`, `total_cost`, `breakdown` (JSONB) |
| `Gamification.Badge` | `badges` | `key`, `name`, `icon`, `criteria` (JSONB) |
| `Gamification.UserBadge` | `user_badges` | `user_id`, `badge_id`, `awarded_at` |
| `Notifications.NotificationRule` | `notification_rules` | `rule_type`, `threshold_value`, `enabled` |
| `Notifications.Notification` | `notifications` | `type`, `title`, `body`, `read_at`, `payload` (JSONB) |
| `Suggestions.Suggestion` | `suggestions` | `suggestion_type`, `title`, `body`, `estimated_saving_weekly`, `dismissed_at` |

### EnergySource metadata shapes (JSONB)

```
electricity: {tariff_kwh, rated_kw, peak_hours: [{from, to, multiplier}], standing_charge_daily?}
gas:         {cost_per_cubic_meter, rated_output_kw, calorific_value}
fuel:        {fuel_type, consumption_per_100km, cost_per_liter, avg_speed_kmh?}
water:       {cost_per_cubic_meter}
heating:     {rated_output_kw, boiler_efficiency}
```

## Async Pipeline (CalculationWorker)

When a user logs usage:

1. `Logs.log_usage/2` inserts `UsageLog` (computed fields nil), enqueues `CalculationWorker`
2. `CalculationWorker` → `Logs.recalculate_log/1` → `Engine.calculate/2` → writes `computed_kwh`/`computed_cost`
3. `Summaries.rebuild_daily_summary/2` for the log's date
4. `Notifications.check_rules_for_user/1`
5. `Gamification.check_and_award_badges/1`
6. `Suggestions.generate_suggestions/1` (debounced: skipped if any suggestion < 6h old)
7. `Phoenix.PubSub.broadcast` on `"user:#{user_id}:log_computed"` → LiveView updates the row

## Oban Queues & Cron

| Queue | Concurrency | Workers |
|-------|-------------|---------|
| `calculations` | 5 | `CalculationWorker` |
| `default` | 10 | `SummaryWorker` |
| `notifications` | 2 | `NotificationWorker` |
| `suggestions` | 2 | `SuggestionWorker` |

Cron schedule (from `config/config.exs`):
- `SummaryWorker` — daily at 00:05 UTC
- `SuggestionWorker` — daily at 02:00 UTC
- `NotificationWorker` (weekly_summary) — Monday 08:00 UTC

## Development Workflow

### First-time setup

```bash
mix deps.get                # Requires hex.pm network access
mix ecto.setup              # Creates DB, runs migrations, seeds badges
mix phx.server              # Start server at http://localhost:4000
```

### Common tasks

```bash
mix test                    # Run all tests (auto-creates test DB)
mix format                  # Format code
mix credo                   # Static analysis
mix dialyzer                # Type checking
mix ecto.reset              # Drop + recreate DB
mix ecto.migrate            # Run pending migrations
```

### Dev tools

- Phoenix LiveDashboard: `http://localhost:4000/dev/dashboard`
- Swoosh local mailbox: `http://localhost:4000/dev/mailbox`

## Database Migrations (in order)

1. `20260101000001` — `users`, `users_tokens`
2. `20260101000002` — `energy_sources`
3. `20260101000003` — `usage_logs`
4. `20260101000004` — `daily_summaries`
5. `20260101000005` — `badges`, `user_badges`
6. `20260101000006` — `notification_rules`, `notifications`
7. `20260101000007` — `suggestions`
8. `20260101000008` — Oban jobs table (`Oban.Migration.up/1`)

## Key Conventions

- **Binary UUIDs everywhere**: `@primary_key {:id, :binary_id, autogenerate: true}` on all schemas
- **Soft deletes for EnergySource**: `active: false` instead of DB deletion (usage logs still reference the source)
- **Context boundaries**: contexts communicate only through public function calls — no cross-context schema imports
- **Denormalized computed fields**: `computed_kwh`/`computed_cost` on `UsageLog` are written once by the worker; historical snapshots are preserved even if tariffs change later
- **PubSub topics**:
  - `"user:#{id}:log_computed"` — broadcast when calculation finishes
  - `"user:#{id}:notifications"` — broadcast when a new notification is created
- **Formatting**: Always run `mix format` before committing. CI enforces `mix format --check-formatted`
- **Secrets**: Never commit `/config/*.secret.exs`
- **Module namespace**: All domain modules under `Pulse.*`, web modules under `PulseWeb.*`

## Environment Variables (production)

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | 64-char random secret (`mix phx.gen.secret`) |
| `PHX_HOST` | Public hostname |
| `PORT` | HTTP port (default: 4000) |
| `SMTP_RELAY` | SMTP server |
| `SMTP_USERNAME` | SMTP username |
| `SMTP_PASSWORD` | SMTP password |
| `SMTP_PORT` | SMTP port (default: 587) |
| `POOL_SIZE` | DB connection pool size |
| `ECTO_IPV6` | Set to `true` for IPv6 database connections |

## Notes for AI Assistants

- The calculation engine (`Pulse.Engine.*`) is **stateless** — no database access. Test it with plain unit tests.
- When adding a new energy source type, add: (1) metadata validation in `EnergySource.validate_metadata_for_type/2`, (2) a new `Engine.calculate/2` clause, (3) a new engine sub-module if logic is non-trivial.
- Badge criteria are data-driven: add a new badge by inserting a row in `seeds.exs` with a `criteria` map and a matching private function clause in `Gamification.criteria_met?/2`.
- LiveViews subscribe to PubSub in `mount/3` when `connected?(socket)` is true — don't subscribe unconditionally.
- The `EnergyChart` LiveView hook receives data via `push_event/3` — always call `push_event("chart_data_updated", ...)` after updating summaries on the socket.
- Update this file when: new contexts are added, new env vars are required, major architectural decisions are made, or new developer workflows are established.
