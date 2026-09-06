# Carbon (Dagster on Fly)

Dagster OSS inside this Pulse repo. It collects US grid carbon intensity and
posts a Flambe observation (`kind=carbon`). It is **not** Dagster+.

This is a **separate Fly app** from Phoenix Pulse. The Machine stays up
(`min_machines_running = 1`, **1 GB**) so the 18:00 UTC schedule can fire and
the UI can boot without nginx 502s.

## Pipeline

1. `us_grid_intensity` — hourly intensity from emission-factors.com for CISO,
   ERCO, PJM, MISO, NYIS (EIA-930, ~24h lag).
2. Unweighted mean of each BA’s UTC-day mean, in **gCO₂eq/kWh**.
3. `flambe_carbon_observation` — `POST /api/observations` (same contract as
   `flambe observe carbon … --on YYYY-MM-DD`).

## Local

```sh
cd carbon
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
pytest
PULSE_CARBON_DRY_RUN=1 dagster dev -m pulse_carbon.definitions
```

## Fly (first time)

From `carbon/`, in region `lhr` like Pulse:

```sh
fly apps create pulse-carbon
fly volumes create dagster_data --size 1 --region lhr --app pulse-carbon
fly secrets set \
  DAGSTER_BASIC_AUTH_USER=... \
  DAGSTER_BASIC_AUTH_PASSWORD=... \
  FLAMBE_URL=https://flambe.fly.dev \
  FLAMBE_API_TOKEN=flb_... \
  --app pulse-carbon
fly deploy --app pulse-carbon
```

Then in the Dagster UI, turn on `daily_us_carbon_schedule`.

UI: `https://pulse-carbon.fly.dev` (HTTP basic auth).

Later deploys: push to `main` (paths under `carbon/`) or
`fly deploy` from this directory.

## Open work

- Pulse: yesterday’s electricity kWh × this observation’s `value` → kgCO₂;
  merge forecast error onto the same `kind=carbon` + `observed_on` row.
