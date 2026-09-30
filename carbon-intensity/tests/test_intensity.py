from datetime import datetime, timezone

import pytest

from carbon_intensity.intensity import (
    USER_AGENT,
    fetch_ba_intensity,
    latest_hour_with_coverage,
    us_hourly_mean,
)


def _payload(ba: str, intensities: list[float], day: str = "2026-09-03") -> dict:
    hourly = []
    for hour, intensity in enumerate(intensities):
        hourly.append(
            {
                "hour_utc": f"{day}T{hour:02d}:00Z",
                "intensity_kg_co2e_per_kwh": intensity,
            }
        )
    return {
        "balancing_authority": ba,
        "ba_name": ba,
        "methodology": "test",
        "hourly": hourly,
    }


def _payload_hours(ba: str, hours: dict[str, float]) -> dict:
    return {
        "balancing_authority": ba,
        "ba_name": ba,
        "methodology": "test",
        "hourly": [
            {"hour_utc": hour, "intensity_kg_co2e_per_kwh": value}
            for hour, value in hours.items()
        ],
    }


def test_us_hourly_mean_is_unweighted_average_of_bas_for_that_hour():
    low = _payload("CISO", [0.1] * 24)
    high = _payload("PJM", [0.3] * 24)
    result = us_hourly_mean(
        [low, high], hour_utc=datetime(2026, 9, 3, 12, tzinfo=timezone.utc)
    )

    assert result["hour_utc"] == "2026-09-03T12:00:00Z"
    assert result["timestamp_ms"] == int(datetime(2026, 9, 3, 12, tzinfo=timezone.utc).timestamp() * 1000)
    assert result["mean_g_per_kwh"] == 200.0
    assert result["min_g_per_kwh"] == 100.0
    assert result["max_g_per_kwh"] == 300.0
    assert result["ba_count"] == 2
    assert result["unit"] == "gCO2eq/kWh"


def test_us_hourly_mean_uses_that_hour_not_the_day_mean():
    varying = _payload("CISO", [0.1] + [0.5] * 23)
    result = us_hourly_mean(
        [varying], hour_utc=datetime(2026, 9, 3, 0, tzinfo=timezone.utc)
    )
    assert result["mean_g_per_kwh"] == 100.0


def test_us_hourly_mean_defaults_to_latest_hour_meeting_min_coverage():
    ciso = _payload("CISO", [0.1] * 24)
    pjm = _payload("PJM", [0.3] * 23)
    result = us_hourly_mean([ciso, pjm])
    assert result["hour_utc"] == "2026-09-03T22:00:00Z"
    assert result["ba_count"] == 2


def test_latest_hour_with_coverage_advances_past_lagging_bas():
    ciso = _payload_hours(
        "CISO",
        {
            "2026-09-29T03:00Z": 0.3,
            "2026-09-29T04:00Z": 0.31,
            "2026-09-29T06:00Z": 0.32,
        },
    )
    erco = _payload_hours(
        "ERCO",
        {"2026-09-29T03:00Z": 0.4, "2026-09-29T04:00Z": 0.41},
    )
    miso = _payload_hours(
        "MISO",
        {"2026-09-29T03:00Z": 0.45, "2026-09-29T04:00Z": 0.46},
    )
    pjm = _payload_hours("PJM", {"2026-09-29T03:00Z": 0.35})
    nyis = _payload_hours("NYIS", {"2026-09-29T03:00Z": 0.25})

    hour = latest_hour_with_coverage([ciso, erco, miso, pjm, nyis], min_bas=3)
    assert hour == datetime(2026, 9, 29, 4, tzinfo=timezone.utc)

    result = us_hourly_mean([ciso, erco, miso, pjm, nyis], min_bas=3)
    assert result["hour_utc"] == "2026-09-29T04:00:00Z"
    assert result["ba_count"] == 3
    assert {row["ba"] for row in result["balancing_authorities"]} == {"CISO", "ERCO", "MISO"}


def test_us_hourly_mean_requires_enough_bas_for_requested_hour():
    with pytest.raises(ValueError, match="need at least"):
        us_hourly_mean(
            [_payload("CISO", [0.1] * 24)],
            hour_utc=datetime(2026, 9, 4, 0, tzinfo=timezone.utc),
        )


class _FakeResponse:
    def __init__(self, payload: dict):
        import json

        self._body = json.dumps(payload).encode("utf-8")

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def test_fetch_ba_intensity_sends_user_agent():
    captured = {}

    def opener(request, timeout=30):
        captured["url"] = request.full_url
        captured["user_agent"] = request.get_header("User-agent")
        captured["accept"] = request.get_header("Accept")
        return _FakeResponse(_payload("CISO", [0.1] * 24))

    payload = fetch_ba_intensity("CISO", hours=24, opener=opener)
    assert payload["balancing_authority"] == "CISO"
    assert captured["url"].endswith("/api/intensity?ba=CISO&hours=24")
    assert captured["user_agent"] == USER_AGENT
    assert captured["accept"] == "application/json"


def test_fetch_ba_intensity_retries_timeouts(monkeypatch):
    attempts = {"count": 0}
    sleeps = []

    def opener(request, timeout=30):
        attempts["count"] += 1
        if attempts["count"] < 3:
            raise TimeoutError("The read operation timed out")
        return _FakeResponse(_payload("CISO", [0.1] * 24))

    monkeypatch.setattr("carbon_intensity.intensity.time.sleep", sleeps.append)

    payload = fetch_ba_intensity("CISO", hours=24, opener=opener)
    assert payload["balancing_authority"] == "CISO"
    assert attempts["count"] == 3
    assert sleeps == [1.0, 2.0]


def test_fetch_ba_intensity_raises_after_retries_exhausted(monkeypatch):
    monkeypatch.setattr("carbon_intensity.intensity.time.sleep", lambda *_: None)

    def opener(request, timeout=30):
        raise TimeoutError("The read operation timed out")

    with pytest.raises(RuntimeError, match="timed out fetching intensity for CISO"):
        fetch_ba_intensity("CISO", hours=24, opener=opener)
