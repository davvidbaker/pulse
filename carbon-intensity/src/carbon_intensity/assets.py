from __future__ import annotations

import os
from pathlib import Path

import dagster as dg

from carbon_intensity.flambe import post_observation
from carbon_intensity.intensity import collect_us_hourly_mean

DEFAULT_LAST_HOUR_PATH = "/data/dagster/last_carbon_hour_utc"


def last_posted_hour_path() -> Path:
    return Path(os.environ.get("CARBON_INTENSITY_LAST_HOUR_PATH", DEFAULT_LAST_HOUR_PATH))


def read_last_posted_hour() -> str | None:
    path = last_posted_hour_path()
    try:
        value = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    return value or None


def write_last_posted_hour(hour_utc: str) -> None:
    path = last_posted_hour_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"{hour_utc}\n", encoding="utf-8")


@dg.asset(group_name="carbon_intensity")
def us_grid_intensity() -> dict:
    """Latest UTC hour with enough BA coverage, averaged across those BAs."""
    return collect_us_hourly_mean()


@dg.asset(group_name="carbon_intensity", deps=[us_grid_intensity])
def flambe_observation(us_grid_intensity: dict) -> dg.MaterializeResult:
    """Insert a Flambe carbon observation for that UTC hour (no observed_on)."""
    hour_utc = us_grid_intensity["hour_utc"]
    payload = {
        "source": "us-ba-mean",
        "hour_utc": hour_utc,
        "bas": [row["ba"] for row in us_grid_intensity["balancing_authorities"]],
        "ba_count": us_grid_intensity.get("ba_count"),
        "ba_g_per_kwh": {
            row["ba"]: row["g_per_kwh"] for row in us_grid_intensity["balancing_authorities"]
        },
        "min_g_per_kwh": us_grid_intensity["min_g_per_kwh"],
        "max_g_per_kwh": us_grid_intensity["max_g_per_kwh"],
        "methodology": us_grid_intensity.get("methodology"),
        "collected_at": us_grid_intensity["collected_at"],
    }

    dry_run = os.environ.get("CARBON_INTENSITY_DRY_RUN") == "1"
    observation_id: int | str | None = None
    if dry_run:
        observation_id = "skipped"
    else:
        last_hour = read_last_posted_hour()
        if last_hour is not None and hour_utc <= last_hour:
            observation_id = "skipped_duplicate_hour"
        else:
            observation_id = post_observation(
                kind="carbon",
                value=us_grid_intensity["mean_g_per_kwh"],
                unit=us_grid_intensity["unit"],
                timestamp=us_grid_intensity["timestamp_ms"],
                payload=payload,
            )
            write_last_posted_hour(hour_utc)

    return dg.MaterializeResult(
        metadata={
            "hour_utc": hour_utc,
            "mean_g_per_kwh": us_grid_intensity["mean_g_per_kwh"],
            "ba_count": us_grid_intensity.get("ba_count"),
            "balancing_authorities": ", ".join(
                row["ba"] for row in us_grid_intensity["balancing_authorities"]
            ),
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
