from datetime import date

import pytest

from pulse_carbon.intensity import USER_AGENT, fetch_ba_intensity, us_daily_mean


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


def test_us_daily_mean_is_unweighted_average_of_ba_day_means():
    low = _payload("CISO", [0.1] * 24)
    high = _payload("PJM", [0.3] * 24)
    result = us_daily_mean([low, high], observed_on=date(2026, 9, 3))

    assert result["observed_on"] == "2026-09-03"
    assert result["mean_g_per_kwh"] == 200.0
    assert result["min_g_per_kwh"] == 100.0
    assert result["max_g_per_kwh"] == 300.0
    assert result["unit"] == "gCO2eq/kWh"


def test_us_daily_mean_ignores_other_utc_days():
    payload = _payload("CISO", [0.1] * 24, day="2026-09-03")
    payload["hourly"].append(
        {"hour_utc": "2026-09-04T00:00Z", "intensity_kg_co2e_per_kwh": 9.9}
    )
    result = us_daily_mean([payload], observed_on=date(2026, 9, 3))
    assert result["mean_g_per_kwh"] == 100.0


def test_us_daily_mean_requires_enough_hours():
    with pytest.raises(ValueError, match="need at least"):
        us_daily_mean([_payload("CISO", [0.1] * 4)], observed_on=date(2026, 9, 3))


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
