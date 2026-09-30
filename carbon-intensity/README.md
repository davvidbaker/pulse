# Carbon intensity (Dagster on Fly)

Dagster OSS inside this Pulse repo. It collects US carbon intensity and posts a
Flambe observation (`kind=carbon`). It is **not** Dagster+.

This is a **separate Fly app** from Phoenix Pulse. The Machine stays up
(`min_machines_running = 1`, **1 GB**) so the hourly schedule can fire and
the UI can boot without nginx 502s.

## Pipeline

1. `us_grid_intensity` — hourly intensity from emission-factors.com for CISO,
   ERCO, PJM, MISO, NYIS (EIA-930, ~24h lag).
2. Unweighted mean of BAs that have the latest UTC hour with coverage from at
   least 3 authorities, in **gCO₂eq/kWh**. (Requiring all five stuck the job
   on lagging BAs such as PJM/NYIS.)
3. `flambe_observation` — `POST /api/observations` (same contract as
   `flambe observe carbon … --at <hour>`). Omits `observed_on` so each hour
   inserts instead of upserting a daily row. Skips re-posting an hour already
   written to `/data/dagster/last_carbon_hour_utc`.

## Local

```sh
cd carbon-intensity
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
pytest
CARBON_INTENSITY_DRY_RUN=1 dagster dev -m carbon_intensity.definitions
```

## Fly (first time)

From `carbon-intensity/`, in region `lhr` like Pulse:

```sh
fly apps create carbon-intensity
fly volumes create dagster_data --size 1 --region lhr --app carbon-intensity
fly secrets set \
  DAGSTER_BASIC_AUTH_USER=... \
  DAGSTER_BASIC_AUTH_PASSWORD=... \
  FLAMBE_URL=https://flambe.fly.dev \
  FLAMBE_API_TOKEN=flb_... \
  --app carbon-intensity
fly deploy --app carbon-intensity
```

`carbon_intensity_schedule` starts as **running** (every hour, UTC). Boot also
calls `dagster schedule start` so a volume that first loaded it as stopped
still ticks.

UI: `https://carbon-intensity.fly.dev` (HTTP basic auth).

Later deploys: push to `main` (paths under `carbon-intensity/`) or
`fly deploy` from this directory.

## Open work

- Pulse: electricity kWh × matching hourly intensity → kgCO₂; hourly carbon
  rows are undated Flambe observations, so a later kgCO₂ / forecast-error
  merge cannot use the old `kind` + `observed_on` day key.
