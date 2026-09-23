from __future__ import annotations

import os

import dagster as dg

from carbon_intensity.flambe import post_observation
from carbon_intensity.intensity import BALANCING_AUTHORITIES, collect_us_hourly_mean


@dg.asset(group_name="carbon_intensity")
def us_grid_intensity() -> dict:
    """Latest UTC hour of EIA-930 intensity, averaged across major US BAs."""
    return collect_us_hourly_mean()


@dg.asset(group_name="carbon_intensity", deps=[us_grid_intensity])
def flambe_observation(us_grid_intensity: dict) -> dg.MaterializeResult:
    """Insert a Flambe carbon observation for that UTC hour (no observed_on)."""
    payload = {
        "source": "us-ba-mean",
        "hour_utc": us_grid_intensity["hour_utc"],
        "bas": [row["ba"] for row in us_grid_intensity["balancing_authorities"]],
        "ba_g_per_kwh": {
            row["ba"]: row["g_per_kwh"] for row in us_grid_intensity["balancing_authorities"]
        },
        "min_g_per_kwh": us_grid_intensity["min_g_per_kwh"],
        "max_g_per_kwh": us_grid_intensity["max_g_per_kwh"],
        "methodology": us_grid_intensity.get("methodology"),
        "collected_at": us_grid_intensity["collected_at"],
    }

    dry_run = os.environ.get("CARBON_INTENSITY_DRY_RUN") == "1"
    observation_id = None
    if not dry_run:
        observation_id = post_observation(
            kind="carbon",
            value=us_grid_intensity["mean_g_per_kwh"],
            unit=us_grid_intensity["unit"],
            timestamp=us_grid_intensity["timestamp_ms"],
            payload=payload,
        )

    return dg.MaterializeResult(
        metadata={
            "hour_utc": us_grid_intensity["hour_utc"],
            "mean_g_per_kwh": us_grid_intensity["mean_g_per_kwh"],
            "balancing_authorities": ", ".join(BALANCING_AUTHORITIES),
            "dry_run": dry_run,
            "observation_id": observation_id if observation_id is not None else "skipped",
        }
    )


carbon_intensity_job = dg.define_asset_job(
    name="carbon_intensity",
    selection=dg.AssetSelection.groups("carbon_intensity"),
)

carbon_intensity_schedule = dg.ScheduleDefinition(
    name="carbon_intensity_schedule",
    job=carbon_intensity_job,
    cron_schedule="0 * * * *",
    execution_timezone="UTC",
    default_status=dg.DefaultScheduleStatus.RUNNING,
)
