# Pulse data platform

Pulse stores observations, assumptions, calculated results and Flambe delivery receipts in its existing Postgres database. Dagster owns the new footprint calculation. Phoenix owns authentication, input forms and displaying stored results. See [ADR-001](adr/001-dagster-energy-platform.md).

## User flow

Open `/footprint` after signing in. Set your accounting timezone in `/settings`, review household/vehicle assumptions, enter observations, and optionally supply personal daily source-energy baselines. `/dashboard` shows the latest daily energy footprint, with legacy emissions reported separately.

The number is an **estimated full-day source-equivalent energy footprint**, not a normalized 0–100 score and not carbon intensity. Unknown categories make it explicitly partial. The modeling range is a scenario envelope, not a statistical confidence interval. Observed-input share describes evidence supporting the estimate; it does not claim upstream energy was directly metered.

A utility bill is entered with its full quantity, covered dates and `household=true`; it is spread uniformly over those dates and allocated by household size. Several disjoint entries within a category/day are summed. They must not be overlapping measurements of the same usage. Coverage is a category/day declaration: `1` means the category total is complete; `0.5` means half is represented. Unknown coverage uses the observation as a lower bound on the full-day baseline. Measured zero is valid.

The same `external_id` updates an imported observation instead of creating a duplicate. Explicit observations take priority over legacy usage logs for that scope. Mark EV charging/local compute as already included in home electricity when applicable. An included observation suppresses the corresponding fraction of the other category's baseline as well. Legacy electric-vehicle zero-energy logs are excluded; enter charging kWh or travel distance with a vehicle model/calibration instead.

## Assets and cadence

`pulse_input_snapshot` → `pulse_normalized_inputs` → `pulse_daily_footprint` → `pulse_daily_result` → `pulse_flambe_delivery`.

- `pulse_refresh_schedule`: every five minutes; imports the input snapshot, normalizes/calibrates, calculates and stores results.
- `pulse_publish_schedule`: hourly at minute 10; publishes stored results and records each delivery receipt.
- `pulse_daily`: manual/backfill execution of all five stages for a local accounting date.
- The existing grid carbon, generation and hub-price assets/schedules remain independent.

Dates are partition labels; Pulse applies the user's timezone to each date. The work list includes the current and previous local days, changed historical days, observations without results and pending deliveries. It processes up to 31 dates per tick, preserving current-day processing. Personal history uses complete observed days from the prior 28 days. Changed results invalidate subsequent history-dependent days.

The deployed `QueuedRunCoordinator` serializes all runs. Keep that behavior while Flambe has no conditional revision-write API. A publisher reads the current stored revision, rejects dirty results, skips acknowledged metrics, and retries unacknowledged metrics. Dated Flambe upserts make failed acknowledgments safe to retry. Pulse calculation succeeds while publishing is disabled or Flambe is unavailable.

Dagster runs on one VM with local workers and a persistent SQLite volume. Startup marks active runs from before the VM boot as interrupted, freeing their queue slots; queued work and workers started since boot are preserved. This recovery assumes one VM owns the instance storage. Revisit it before moving to shared storage or remote workers.

Pulse jobs use one process per run for their small sequential API/model steps, avoiding Python startup for every asset. The runtime has two shared CPUs and 2 GB RAM for the webserver, daemon, code location and active worker.

## Service configuration

Phoenix requires its production database and endpoint settings. SMTP is optional: configure both `SMTP_USERNAME` and `SMTP_PASSWORD` to enable email. Without them, email delivery returns an explicit error; registration and password login remain available. Password reset emails require SMTP. Add these **secrets**, never committed values:

| Phoenix | Meaning |
| --- | --- |
| `PULSE_PLATFORM_TOKEN` | At least 32 random characters; shared only with the selected Dagster deployment |
| `PULSE_PLATFORM_USER_ID` | UUID of the Pulse account authorized for that token |

| Dagster | Meaning |
| --- | --- |
| `PULSE_URL` | HTTPS origin of the deployed Phoenix app; localhost HTTP is allowed for development |
| `PULSE_PLATFORM_TOKEN` | Matching service token |
| `PULSE_PUBLISH_ENABLED` | Set to `1` only after the Pulse account and Flambe destination are bound |
| `FLAMBE_URL` | `https://flambe.fly.dev` for Cloud |
| `FLAMBE_API_TOKEN` | Credential for the same intended person's Flambe account |

There are no network calls or credential requirements at definition load. Missing Pulse configuration makes schedules skip. This first service binding is deliberately single-user; it must not be used to impersonate arbitrary user IDs from request parameters. Browser sessions do not authenticate service endpoints.

Flambe receives `pulse_energy`, `pulse_energy_lower`, `pulse_energy_upper`, `pulse_scope_coverage` and `pulse_observed_fraction`. The date key is `observed_on`; category details, missing scopes, methodology version, revision and uncertainty are in payloads. Missing categories do not become misleading zero-valued category series. Carbon remains a different kind/unit.

## API contract

Every route below uses `Authorization: Bearer <service token>`:

- `GET /api/platform/work`: accounting dates needing work.
- `GET /api/platform/inputs/:date`: raw observations, profile, complete-day history and snapshot hash.
- `PUT /api/platform/results/:date`: persist a calculated result, rejecting a changed input hash with HTTP 409.
- `GET /api/platform/results/:date`: latest persisted result with revision, dirty status and receipts.
- `POST /api/platform/results/:date/receipts`: acknowledge `{revision, kind, observation_id}`.
- `POST /api/platform/observations`: import `{observation: {...}}` for the bound user.

Example imported observation (no real personal data):

```json
{"observation":{"external_id":"meter-example-2026-10","scope":"home_electricity","starts_on":"2026-10-01","ends_on":"2026-10-31","quantity":310,"unit":"kwh","basis":"electricity","coverage":1,"allocation":1,"household":true,"quality":"measured","source_ref":"utility statement"}}
```

Accepted categories are home electricity, home heating, ground travel, food, remote compute, flights, goods and services. Built-in units include kWh, travel km/liters, heating therms and food meals. Custom units such as item, night, hour or request need an explicit energy factor and source reference. There is no universal AI prompt factor. Source adapters for actual personal providers can post through this same ingestion endpoint; utility/GPS/food/cloud account connections are not bundled or automatically authorized by this change.

## Versioned starting assumptions

- Household allocation initially assumes **2.5 people**, a visible modeling assumption to replace.
- Home electricity: [EIA](https://www.eia.gov/energyexplained/use-of-energy/electricity-use-in-homes.php), approximately 10,500 household kWh/year, divided by household size.
- Gas heating, if selected: [EIA RECS 2020](https://www.eia.gov/todayinenergy/detail.php?id=57321), 56.6 MMBtu/year among gas-using households. This is a coarse annual average, not a weather-specific prediction.
- Grid conversion 2.8 and gas conversion 1.05 follow the documented [ENERGY STAR convention](https://www.energystar.gov/sites/default/files/asset/document/BPS-White_paper_final.pdf). Source-equivalent energy is an approximation; fuel transport factors omit extraction/refining and goods infrastructure is not inferred.
- Travel: [FHWA 2024](https://www.fhwa.dot.gov/policyinformation/pubs/our_nations_highways_2026/drivers.cfm), 13,735 vehicle-miles per licensed driver/year. The initial **0.7 fuel kWh/km is an agent-selected generic vehicle proxy**, not a measured fleet average. A personal calibration takes priority; an optional FuelEconomy.gov vehicle ID supplies model/year efficiency if no calibration is present. Provider outages get a labeled fallback. Vehicle occupancy is represented by observation allocation.
- Food: [USDA RRFD](https://www.ers.usda.gov/data-products/resource-requirements-of-food-demand), release 2026-03-17, 2023 table Xf0000, source TOTAL. Annual total 10,144,929.951 billion Btu minus household transportation 836,028.356, kitchen equipment 289,471.150 and kitchen utilities 1,318,109.168. Divide by [2023 population 334,914,895](https://www.census.gov/newsroom/facts-for-features/2024/fourth-of-july.html) and 365, converting billion Btu to kWh with 293,071.07. A generic meal is one third of that daily estimate. This is a modeled US food-system average, not a particular meal measurement.
- Remote compute, flights, goods and services have no invented population priors. Explicit observations, personal baselines or complete personal history supply them.

## Verification and activation

```sh
cd carbon-intensity
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
export DAGSTER_HOME="$(pwd)/.dagster-local"
mkdir -p "$DAGSTER_HOME"
printf 'telemetry:\n  enabled: false\n' > "$DAGSTER_HOME/dagster.yaml"
.venv/bin/dg check defs
.venv/bin/pytest
```

For Phoenix, run `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors` and `mix test` with Postgres. `PULSE_TEST_DB_PORT` optionally selects an isolated test database port.

Activation order: provision or identify the Phoenix app/database; configure its existing production environment; deploy and migrate; register/select the intended Pulse account; bind the service token/user ID; configure Dagster's Pulse origin/token; run one day with publishing disabled and review the stored result; confirm the Flambe credential identity; enable publishing and verify the five dated observations and their receipts. Never create personal baseline observations from test fixtures.

Pulse's public origin is `https://pulse.brainsand.space`, hosted by the Fly app `pulse-david-baker` with a dedicated `pulse-postgres` database in the personal organization. Browser links on the old Fly hostname redirect to the public origin, preserving paths and queries. Service API calls remain compatible during the transition; set Dagster's `PULSE_URL` to the public origin after DNS and HTTPS are verified. The maintained Dagster deployment is `carbon-intensity`. Deployment credentials must be authorized for the corresponding app; CI uses `PULSE_FLY_API_TOKEN` for Phoenix and the existing `FLY_API_TOKEN` for Dagster.

Namecheap DNS: add CNAME `pulse` → `yj8wm9n.pulse-david-baker.fly.dev` (automatic TTL). Fly manages the certificate for `pulse.brainsand.space`. Verify DNS and certificate readiness before deploying the canonical hostname configuration.

### Dashboard period averages

The dashboard reads saved daily results for today, the calendar week (Monday
through today), or month to date. Average watts is the sum of source kWh times
1,000, divided by the actual local-day hours of available results (including DST).
Today's result remains a full-day estimate. Missing dates and results saved for a
different account timezone are unavailable, never zero-filled; the UI shows
coverage and gaps. Category totals and scenario bounds use those same available
days; observed share is energy-weighted. These are presentation aggregates and do
not change the canonical daily calculation or the metrics published to Flambe.
