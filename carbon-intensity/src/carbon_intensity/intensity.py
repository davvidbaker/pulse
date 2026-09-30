"""Fetch and average EIA-930-derived US grid carbon intensity."""

from __future__ import annotations

import json
import statistics
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

INTENSITY_URL = "https://emission-factors.com/api/intensity"
BALANCING_AUTHORITIES = ("CISO", "ERCO", "PJM", "MISO", "NYIS")
KG_TO_G = 1000.0
USER_AGENT = "carbon-intensity/0.1 (+https://github.com/davvidbaker/pulse)"
FETCH_TIMEOUT_SECONDS = 30
FETCH_ATTEMPTS = 3
FETCH_RETRY_BACKOFF_SECONDS = (1.0, 2.0)


def fetch_ba_intensity(ba: str, hours: int = 72, opener=None) -> dict[str, Any]:
    url = f"{INTENSITY_URL}?ba={ba}&hours={hours}"
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    reader = opener or urllib.request.urlopen
    last_error: BaseException | None = None

    for attempt in range(FETCH_ATTEMPTS):
        try:
            with reader(request, timeout=FETCH_TIMEOUT_SECONDS) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"HTTP {exc.code} {exc.reason} fetching intensity for {ba}") from exc
        except (TimeoutError, urllib.error.URLError, OSError) as exc:
            last_error = exc
            if attempt >= FETCH_ATTEMPTS - 1:
                break
            time.sleep(FETCH_RETRY_BACKOFF_SECONDS[min(attempt, len(FETCH_RETRY_BACKOFF_SECONDS) - 1)])

    raise RuntimeError(
        f"timed out fetching intensity for {ba} after {FETCH_ATTEMPTS} attempts"
    ) from last_error


def parse_hour_utc(hour_utc: str) -> datetime:
    return datetime.fromisoformat(hour_utc.replace("Z", "+00:00")).astimezone(timezone.utc)


def coerce_utc_hour(stamp: datetime) -> datetime:
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    else:
        stamp = stamp.astimezone(timezone.utc)
    return stamp.replace(minute=0, second=0, microsecond=0)


def format_hour_utc(stamp: datetime) -> str:
    return coerce_utc_hour(stamp).strftime("%Y-%m-%dT%H:00:00Z")


def intensity_by_hour(payload: dict[str, Any]) -> dict[datetime, float]:
    by_hour: dict[datetime, float] = {}
    for hour in payload.get("hourly") or []:
        hour_utc = hour.get("hour_utc")
        intensity = hour.get("intensity_kg_co2e_per_kwh")
        if not hour_utc or intensity is None:
            continue
        by_hour[coerce_utc_hour(parse_hour_utc(hour_utc))] = float(intensity) * KG_TO_G
    return by_hour


def latest_complete_hour(payloads: list[dict[str, Any]]) -> datetime:
    if not payloads:
        raise ValueError("no intensity payloads")
    common: set[datetime] | None = None
    for payload in payloads:
        hours = set(intensity_by_hour(payload))
        common = hours if common is None else common & hours
    if not common:
        raise ValueError("no UTC hour has coverage across all balancing authorities")
    return max(common)


def us_hourly_mean(
    payloads: list[dict[str, Any]], hour_utc: datetime | None = None
) -> dict[str, Any]:
    if not payloads:
        raise ValueError("no intensity payloads")
    hour_utc = coerce_utc_hour(hour_utc or latest_complete_hour(payloads))
    per_ba = []
    for payload in payloads:
        by_hour = intensity_by_hour(payload)
        ba = payload.get("balancing_authority") or "unknown"
        if hour_utc not in by_hour:
            raise ValueError(f"{ba} is missing intensity for {format_hour_utc(hour_utc)}")
        per_ba.append(
            {
                "ba": ba,
                "ba_name": payload.get("ba_name"),
                "g_per_kwh": round(by_hour[hour_utc], 1),
            }
        )
    means = [row["g_per_kwh"] for row in per_ba]
    return {
        "hour_utc": format_hour_utc(hour_utc),
        "timestamp_ms": int(hour_utc.timestamp() * 1000),
        "unit": "gCO2eq/kWh",
        "mean_g_per_kwh": round(statistics.fmean(means), 1),
        "min_g_per_kwh": round(min(means), 1),
        "max_g_per_kwh": round(max(means), 1),
        "balancing_authorities": per_ba,
        "source": "emission-factors.com",
        "methodology": payloads[0].get("methodology"),
        "collected_at": datetime.now(timezone.utc).isoformat(),
    }


def collect_us_hourly_mean(hours: int = 72, opener=None) -> dict[str, Any]:
    payloads = [fetch_ba_intensity(ba, hours=hours, opener=opener) for ba in BALANCING_AUTHORITIES]
    return us_hourly_mean(payloads)
