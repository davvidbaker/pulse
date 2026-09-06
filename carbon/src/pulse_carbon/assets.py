from __future__ import annotations

import os

import dagster as dg

from pulse_carbon.flambe import post_observation
from pulse_carbon.intensity import BALANCING_AUTHORITIES, collect_us_daily_mean


@dg.asset(group_name="carbon")
def us_grid_intensity() -> dict:
    """Hourly EIA-930 intensity for major US BAs, averaged to one UTC day."""
    return collect_us_daily_mean()


@dg.asset(group_name="carbon", deps=[us_grid_intensity])
def flambe_carbon_observation(us_grid_intensity: dict) -> dg.MaterializeResult:
    """Upsert Flambe observation kind=carbon for that UTC day."""
    payload = {
        "source": "us-ba-mean",
        "bas": [row["ba"] for row in us_grid_intensity["balancing_authorities"]],
        "ba_means_g_per_kwh": {
            row["ba"]: row["mean_g_per_kwh"]
            for row in us_grid_intensity["balancing_authorities"]
        },
        "min_g_per_kwh": us_grid_intensity["min_g_per_kwh"],
        "max_g_per_kwh": us_grid_intensity["max_g_per_kwh"],
        "methodology": us_grid_intensity.get("methodology"),
        "collected_at": us_grid_intensity["collected_at"],
    }

    dry_run = os.environ.get("PULSE_CARBON_DRY_RUN") == "1"
    observation_id = None
    if not dry_run:
        observation_id = post_observation(
            kind="carbon",
            value=us_grid_intensity["mean_g_per_kwh"],
            unit=us_grid_intensity["unit"],
            observed_on=us_grid_intensity["observed_on"],
            payload=payload,
        )

    return dg.MaterializeResult(
        metadata={
            "observed_on": us_grid_intensity["observed_on"],
            "mean_g_per_kwh": us_grid_intensity["mean_g_per_kwh"],
            "balancing_authorities": ", ".join(BALANCING_AUTHORITIES),
            "dry_run": dry_run,
            "observation_id": observation_id if observation_id is not None else "skipped",
        }
    )


daily_carbon_job = dg.define_asset_job(
    name="daily_us_carbon",
    selection=dg.AssetSelection.groups("carbon"),
)

daily_carbon_schedule = dg.ScheduleDefinition(
    name="daily_us_carbon_schedule",
    job=daily_carbon_job,
    cron_schedule="0 18 * * *",
    execution_timezone="UTC",
    default_status=dg.DefaultScheduleStatus.RUNNING,
)
