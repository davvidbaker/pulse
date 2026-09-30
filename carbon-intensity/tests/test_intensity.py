from datetime import datetime, timezone

import pytest

from carbon_intensity.intensity import USER_AGENT, fetch_ba_intensity, us_hourly_mean


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
    assert result["unit"] == "gCO2eq/kWh"


def test_us_hourly_mean_uses_that_hour_not_the_day_mean():
    varying = _payload("CISO", [0.1] + [0.5] * 23)
    result = us_hourly_mean(
        [varying], hour_utc=datetime(2026, 9, 3, 0, tzinfo=timezone.utc)
    )
    assert result["mean_g_per_kwh"] == 100.0


def test_us_hourly_mean_defaults_to_latest_hour_all_bas_share():
    ciso = _payload("CISO", [0.1] * 24)
    pjm = _payload("PJM", [0.3] * 23)
    result = us_hourly_mean([ciso, pjm])
    assert result["hour_utc"] == "2026-09-03T22:00:00Z"


def test_us_hourly_mean_requires_the_hour_on_every_ba():
    with pytest.raises(ValueError, match="missing intensity"):
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
