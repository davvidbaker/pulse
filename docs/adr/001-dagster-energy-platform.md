# ADR-001: Dagster computes Pulse footprints; Pulse stores and serves them

Status: Accepted direction; implementation conventions below are agent-selected and documented for review.

## Context and decision

David requested a continuously updated daily personal energy footprint, asked for Dagster as the data platform, and confirmed that Pulse stores the data. Pulse already has a Phoenix/Postgres backend and a separate Dagster OSS deployment publishing hourly grid carbon intensity to Flambe Cloud.

Keep Phoenix/Postgres authoritative for raw observations, profile assumptions, calculated daily results and delivery receipts. Dagster owns normalization, factor application, estimate replacement, daily footprint calculation, backfills and publishing. Phoenix serves forms and results; it does not duplicate the new footprint formula. Dagster accesses a narrowly authenticated, single-user-scoped API instead of receiving direct database credentials. The existing carbon collector continues independently.

Pulse pushes results through its Dagster publisher to Flambe's generic observations API. Flambe polling was considered; it would fit consumer-managed connectors, but would move scheduling and Pulse-specific freshness handling into Flambe. Calculating a score must succeed independently of Flambe availability. Stored results remain pending until all observations have delivery receipts; retries read the latest result. Serialize platform runs to prevent an older run overwriting newer observations.

## Calculation conventions

The headline is an estimated full-day energy footprint in source-equivalent kWh/day. This follows David's energy request; carbon remains a separate quantity and no combined index is introduced. Preserve raw units and each applied factor, provenance and accounting scope. Source/site conversions are a versioned approximation, not a complete lifecycle assessment. Unsupported categories remain visibly missing rather than zero.

Use distinct accounting scopes (home electricity, home heating, ground travel, food, remote compute, flights, goods, services). For each scope, complete observations replace the day's baseline; partial observations replace only their stated fraction. Measured zero is valid. Source quality is separate from time coverage. User entries take precedence over imported legacy logs for the same scope. Household electricity includes local devices/cooking and optionally EV charging; included activities are retained for attribution but excluded from additive totals. Food priors exclude household transportation, kitchen equipment and utilities. Goods may be allocated over an explicitly supplied service period.

Fallback order: complete/partial observations, personal complete-day history, explicit personal baseline, then documented US population/model priors. Flights, goods, services and remote compute receive no invented generic energy factors. User-supplied source-energy estimates and factors support all categories. Every incomplete result is labeled partial and publishes its missing scopes and estimation provenance.

## Consequences and validation

Phoenix remains usable without Dagster; displayed results show their calculation time and stale input status. Dagster availability controls new footprint calculations and publishing. An operator must bind the Pulse service token to a specific user and supply that person's Flambe credential. No personal usage or credentials are seeded.

Daily inputs use the profile's IANA timezone and actual local-day bounds, including DST. Snapshot hashes reject results calculated from changed inputs. Dated Flambe observations upsert the latest daily value; detailed revisions remain in Pulse. Hourly runs recalculate recent days and any historical days with changed inputs or pending delivery.

Validate replacement/coverage rules, household allocation, invalid factors, missing scopes, DST, user isolation, stale snapshots, delivery failures and retries, and loading/materializing the Dagster definitions before deployment.
