"""Collect hourly grid generation and representative day-ahead hub prices."""

from __future__ import annotations

import statistics
import warnings
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Callable

import pandas as pd
from gridstatus import CAISO, Ercot, MISO, Markets, NYISO

PRICE_SOURCES = (
    ("CAISO", ("TH_NP15_GEN-APND", "TH_SP15_GEN-APND", "TH_ZP26_GEN-APND")),
    ("MISO", ("ILLINOIS.HUB", "MICHIGAN.HUB", "TEXAS.HUB")),
    ("ERCOT", ("HB_NORTH", "HB_HOUSTON", "HB_SOUTH", "HB_WEST")),
)

META_COLUMNS = {
    "Time",
    "Interval Start",
    "Interval End",
    "Publish Time",
    "Market",
    "Location",
    "Location Type",
    "Node",
    "Load",
    "Imports",
}


def _utc_hour(value: Any) -> datetime:
    stamp = pd.Timestamp(value)
    if stamp.tzinfo is None:
        stamp = stamp.tz_localize("UTC")
    else:
        stamp = stamp.tz_convert("UTC")
    return stamp.floor("h").to_pydatetime()


def _format_hour_utc(stamp: datetime) -> str:
    return stamp.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:00:00Z")


def _hourly_price_rows(
    frame: pd.DataFrame,
    source: str,
    aliases: dict[str, str] | None = None,
) -> dict[datetime, dict[str, float]]:
    if frame.empty or "Interval Start" not in frame.columns:
        return {}

    location_col = "Location" if "Location" in frame.columns else "Node"
    value_col = "LMP" if "LMP" in frame.columns else "SPP"
    if location_col not in frame.columns or value_col not in frame.columns:
        return {}

    aliases = aliases or {}
    by_hour: dict[datetime, dict[str, float]] = defaultdict(dict)
    for _, row in frame.iterrows():
        location = str(row[location_col])
        value = pd.to_numeric(row[value_col], errors="coerce")
        if pd.isna(value):
            continue
        label = aliases.get(location, location)
        by_hour[_utc_hour(row["Interval Start"])][f"{source} · {label}"] = round(float(value), 2)
    return dict(by_hour)


def _hourly_generation_rows(frame: pd.DataFrame, source: str) -> dict[datetime, float]:
    if frame.empty:
        return {}

    time_col = "Interval Start" if "Interval Start" in frame.columns else "Time"
    if time_col not in frame.columns:
        return {}

    numeric_cols = [
        column
        for column in frame.columns
        if column not in META_COLUMNS and pd.api.types.is_numeric_dtype(frame[column])
    ]
    if not numeric_cols:
        return {}

    working = frame[[time_col, *numeric_cols]].copy()
    for column in numeric_cols:
        working[column] = pd.to_numeric(working[column], errors="coerce")
    working["total_generation_mw"] = working[numeric_cols].sum(axis=1, min_count=1)
    working["hour_utc"] = working[time_col].map(_utc_hour)
    hourly = working.groupby("hour_utc", sort=True)["total_generation_mw"].mean().dropna()
    return {hour: round(float(value), 1) for hour, value in hourly.items()}


def _latest_hour_with_sources(
    series_by_source: dict[str, dict[datetime, Any]],
    now: datetime,
    min_sources: int = 2,
) -> datetime:
    current_hour = _utc_hour(now)
    coverage: dict[datetime, set[str]] = defaultdict(set)
    for source, rows in series_by_source.items():
        for hour in rows:
            if hour <= current_hour:
                coverage[hour].add(source)

    if not coverage:
        raise ValueError("no hourly market data at or before the current UTC hour")

    required = min(min_sources, len(series_by_source))
    eligible = [hour for hour, sources in coverage.items() if len(sources) >= required]
    if not eligible:
        best_count = max(len(sources) for sources in coverage.values())
        eligible = [hour for hour, sources in coverage.items() if len(sources) == best_count]
    return max(eligible)


def _fetch_price_frames() -> dict[str, pd.DataFrame | BaseException]:
    frames: dict[str, pd.DataFrame | BaseException] = {}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        fetches = {
            "CAISO": lambda: CAISO().get_lmp(
                date="today",
                market=Markets.DAY_AHEAD_HOURLY,
                locations=list(PRICE_SOURCES[0][1]),
                sleep=0,
            ),
            "MISO": lambda: MISO().get_lmp(
                date="today",
                market=Markets.DAY_AHEAD_HOURLY,
                locations=list(PRICE_SOURCES[1][1]),
            ),
            "ERCOT": lambda: Ercot().get_spp(
                date="today",
                market=Markets.DAY_AHEAD_HOURLY,
                locations=list(PRICE_SOURCES[2][1]),
                location_type="Trading Hub",
            ),
        }
        for source, fetch in fetches.items():
            try:
                frames[source] = fetch()
            except BaseException as exc:
                frames[source] = exc
    return frames


def collect_hourly_hub_prices(
    *,
    now: datetime | None = None,
    fetcher: Callable[[], dict[str, pd.DataFrame | BaseException]] | None = None,
) -> dict[str, Any]:
    """Representative day-ahead hub prices for the latest well-covered UTC hour."""
    now = now or datetime.now(timezone.utc)
    frames = (fetcher or _fetch_price_frames)()

    per_source: dict[str, dict[datetime, dict[str, float]]] = {}
    errors: dict[str, str] = {}
    for source, frame in frames.items():
        if isinstance(frame, BaseException):
            errors[source] = str(frame)
            continue
        try:
            rows = _hourly_price_rows(
                frame,
                source,
                aliases={
                    "TH_NP15_GEN-APND": "NP15",
                    "TH_SP15_GEN-APND": "SP15",
                    "TH_ZP26_GEN-APND": "ZP26",
                },
            )
            if rows:
                per_source[source] = rows
        except Exception as exc:  # one ISO should not erase the others
            errors[source] = str(exc)

    if not per_source:
        raise ValueError(f"no hub price data returned: {errors}")

    hour = _latest_hour_with_sources(per_source, now)
    series: dict[str, float] = {}
    contributing_sources = []
    for source, rows in per_source.items():
        if hour in rows:
            series.update(rows[hour])
            contributing_sources.append(source)

    values = list(series.values())
    return {
        "hour_utc": _format_hour_utc(hour),
        "timestamp_ms": int(hour.timestamp() * 1000),
        "unit": "$/MWh",
        "mean_value": round(statistics.fmean(values), 2),
        "series": series,
        "source_count": len(contributing_sources),
        "sources": contributing_sources,
        "errors": errors,
        "methodology": "Day-ahead hourly trading-hub prices from ISO public feeds via gridstatus.",
        "collected_at": datetime.now(timezone.utc).isoformat(),
    }


def _fetch_generation_frames() -> dict[str, pd.DataFrame | BaseException]:
    frames: dict[str, pd.DataFrame | BaseException] = {}
    fetches = {
        "CAISO": lambda: CAISO().get_fuel_mix("today"),
        "MISO": lambda: MISO().get_fuel_mix("today"),
        "ERCOT": lambda: Ercot().get_fuel_mix("latest"),
        "NYISO": lambda: NYISO().get_fuel_mix("today"),
    }
    for source, fetch in fetches.items():
        try:
            frames[source] = fetch()
        except BaseException as exc:
            frames[source] = exc
    return frames


def collect_hourly_generation(
    *,
    now: datetime | None = None,
    fetcher: Callable[[], dict[str, pd.DataFrame | BaseException]] | None = None,
) -> dict[str, Any]:
    """Mean total generation MW within the latest well-covered UTC hour."""
    now = now or datetime.now(timezone.utc)
    frames = (fetcher or _fetch_generation_frames)()

    per_source: dict[str, dict[datetime, float]] = {}
    errors: dict[str, str] = {}
    for source, frame in frames.items():
        if isinstance(frame, BaseException):
            errors[source] = str(frame)
            continue
        try:
            rows = _hourly_generation_rows(frame, source)
            if rows:
                per_source[source] = rows
        except Exception as exc:
            errors[source] = str(exc)

    if not per_source:
        raise ValueError(f"no generation data returned: {errors}")

    hour = _latest_hour_with_sources(per_source, now)
    series = {
        source: rows[hour]
        for source, rows in per_source.items()
        if hour in rows
    }
    values = list(series.values())
    return {
        "hour_utc": _format_hour_utc(hour),
        "timestamp_ms": int(hour.timestamp() * 1000),
        "unit": "MW",
        "mean_value": round(statistics.fmean(values), 1),
        "series": series,
        "source_count": len(series),
        "sources": list(series),
        "errors": errors,
        "methodology": "Hourly mean of published fuel-mix generation MW, summed across fuels; imports excluded.",
        "collected_at": datetime.now(timezone.utc).isoformat(),
    }
