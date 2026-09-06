# pulse

Pulse is a Phoenix application for tracking energy usage, costs, summaries, suggestions, and notifications.

## Requirements

- Elixir and Erlang/OTP compatible with `mix.exs`
- PostgreSQL
- Homebrew PostgreSQL or Docker if you want a quick local database

## Local setup

The app expects this development database configuration from [config/dev.exs](/Users/david/code/pulse/config/dev.exs:1):

- host: `localhost`
- port: `5432`
- username: `postgres`
- password: `postgres`
- database: `pulse_dev`

### Option 1: Homebrew PostgreSQL

Start PostgreSQL:

```bash
brew services start postgresql@15
```

Create the role and databases the app expects:

```bash
psql -d postgres -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN CREATE ROLE postgres WITH LOGIN PASSWORD 'postgres' SUPERUSER; END IF; END \$\$;"
psql -d postgres -c "CREATE DATABASE pulse_dev OWNER postgres;"
psql -d postgres -c "CREATE DATABASE pulse_test OWNER postgres;"
```

Then run:

```bash
mix setup
mix phx.server
```

### Option 2: Docker

If you prefer Docker, make sure the Docker daemon is running and then start Postgres:

```bash
docker run --name pulse-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=pulse_dev \
  -p 5432:5432 \
  -d postgres:16
```

Create the test database:

```bash
psql postgresql://postgres:postgres@localhost:5432/postgres -c "CREATE DATABASE pulse_test OWNER postgres;"
```

Then run:

```bash
mix setup
mix phx.server
```

## Current setup notes

- `mix setup` currently requires a running PostgreSQL instance.
- The repo still has compile warnings that do not block boot.

## Carbon (Dagster on Fly)

US grid intensity collection lives in [`carbon/`](carbon/README.md). It is a
separate always-on Fly app (`pulse-carbon`), not Dagster+ and not inside the
Phoenix Machine.
