from datetime import datetime, timezone

import pandas as pd

from carbon_intensity.market_data import (
    collect_hourly_generation,
    collect_hourly_hub_prices,
)


def test_collect_hourly_hub_prices_keeps_named_series_for_same_hour():
    def fetcher():
        return {
            "CAISO": pd.DataFrame(
                {
                    "Interval Start": [
                        "2026-10-01T10:00:00Z",
                        "2026-10-01T10:00:00Z",
                        "2026-10-01T11:00:00Z",
                        "2026-10-01T11:00:00Z",
                    ],
                    "Location": [
                        "TH_NP15_GEN-APND",
                        "TH_SP15_GEN-APND",
                        "TH_NP15_GEN-APND",
                        "TH_SP15_GEN-APND",
                    ],
                    "LMP": [31.0, 29.0, 44.0, 41.0],
                }
            ),
            "MISO": pd.DataFrame(
                {
                    "Interval Start": ["2026-10-01T11:00:00Z"],
                    "Node": ["ILLINOIS.HUB"],
                    "LMP": [38.0],
                }
            ),
            "ERCOT": RuntimeError("temporary source failure"),
        }

    result = collect_hourly_hub_prices(
        now=datetime(2026, 10, 1, 11, 15, tzinfo=timezone.utc),
        fetcher=fetcher,
    )

    assert result["hour_utc"] == "2026-10-01T11:00:00Z"
    assert result["unit"] == "$/MWh"
    assert result["series"] == {
        "CAISO · NP15": 44.0,
        "CAISO · SP15": 41.0,
        "MISO · ILLINOIS.HUB": 38.0,
    }
    assert result["source_count"] == 2
    assert "ERCOT" in result["errors"]


def test_collect_hourly_generation_averages_5_minute_samples_within_hour():
    def fetcher():
        return {
            "CAISO": pd.DataFrame(
                {
                    "Interval Start": [
                        "2026-10-01T10:05:00Z",
                        "2026-10-01T10:55:00Z",
                    ],
                    "Solar": [100.0, 140.0],
                    "Natural Gas": [200.0, 220.0],
                }
            ),
            "MISO": pd.DataFrame(
                {
                    "Interval Start": [
                        "2026-10-01T10:10:00Z",
                        "2026-10-01T10:50:00Z",
                    ],
                    "Coal": [300.0, 340.0],
                    "Wind": [100.0, 120.0],
                    "Imports": [999.0, 999.0],
                }
            ),
        }

    result = collect_hourly_generation(
        now=datetime(2026, 10, 1, 11, 5, tzinfo=timezone.utc),
        fetcher=fetcher,
    )

    assert result["hour_utc"] == "2026-10-01T10:00:00Z"
    assert result["series"] == {
        "CAISO": 330.0,
        "MISO": 430.0,
    }
    assert result["mean_value"] == 380.0
    assert result["unit"] == "MW"
