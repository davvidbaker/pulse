"""Fetch and average EIA-930-derived US grid carbon intensity."""

from __future__ import annotations

import json
import statistics
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import date, datetime, timezone
from typing import Any

INTENSITY_URL = "https://emission-factors.com/api/intensity"
BALANCING_AUTHORITIES = ("CISO", "ERCO", "PJM", "MISO", "NYIS")
KG_TO_G = 1000.0
MIN_HOURS = 18
USER_AGENT = "pulse-carbon/0.1 (+https://github.com/davvidbaker/pulse)"


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
    try:
        with reader(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code} {exc.reason} fetching intensity for {ba}") from exc


def hours_for_utc_date(payload: dict[str, Any], observed_on: date) -> list[dict[str, Any]]:
    matched = []
    for hour in payload.get("hourly") or []:
        hour_utc = hour.get("hour_utc")
        if not hour_utc:
            continue
        stamp = datetime.fromisoformat(hour_utc.replace("Z", "+00:00"))
        if stamp.date() == observed_on:
            matched.append(hour)
    return matched


def mean_g_per_kwh(hours: list[dict[str, Any]]) -> float:
    values = [
        float(hour["intensity_kg_co2e_per_kwh"]) * KG_TO_G
        for hour in hours
        if hour.get("intensity_kg_co2e_per_kwh") is not None
    ]
    if len(values) < MIN_HOURS:
        raise ValueError(f"need at least {MIN_HOURS} hourly points, got {len(values)}")
    return round(statistics.fmean(values), 1)


def latest_complete_utc_date(payloads: list[dict[str, Any]]) -> date:
    counts: dict[date, int] = defaultdict(int)
    for payload in payloads:
        for hour in payload.get("hourly") or []:
            hour_utc = hour.get("hour_utc")
            if not hour_utc:
                continue
            stamp = datetime.fromisoformat(hour_utc.replace("Z", "+00:00"))
            counts[stamp.date()] += 1
    complete = [day for day, count in counts.items() if count >= MIN_HOURS * len(payloads)]
    if not complete:
        raise ValueError("no UTC date has enough hourly coverage across balancing authorities")
    return max(complete)


def us_daily_mean(payloads: list[dict[str, Any]], observed_on: date | None = None) -> dict[str, Any]:
    if not payloads:
        raise ValueError("no intensity payloads")
    observed_on = observed_on or latest_complete_utc_date(payloads)
    per_ba = []
    for payload in payloads:
        hours = hours_for_utc_date(payload, observed_on)
        ba = payload.get("balancing_authority") or "unknown"
        mean = mean_g_per_kwh(hours)
        per_ba.append(
            {
                "ba": ba,
                "ba_name": payload.get("ba_name"),
                "hours": len(hours),
                "mean_g_per_kwh": mean,
            }
        )
    means = [row["mean_g_per_kwh"] for row in per_ba]
    return {
        "observed_on": observed_on.isoformat(),
        "unit": "gCO2eq/kWh",
        "mean_g_per_kwh": round(statistics.fmean(means), 1),
        "min_g_per_kwh": round(min(means), 1),
        "max_g_per_kwh": round(max(means), 1),
        "balancing_authorities": per_ba,
        "source": "emission-factors.com",
        "methodology": payloads[0].get("methodology"),
        "collected_at": datetime.now(timezone.utc).isoformat(),
    }


def collect_us_daily_mean(hours: int = 72, opener=None) -> dict[str, Any]:
    payloads = [fetch_ba_intensity(ba, hours=hours, opener=opener) for ba in BALANCING_AUTHORITIES]
    return us_daily_mean(payloads)
