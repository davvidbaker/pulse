from datetime import date

import pytest

from pulse_carbon.intensity import us_daily_mean


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
