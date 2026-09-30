from pathlib import Path

from carbon_intensity.assets import (
    flambe_observation,
    read_last_posted_hour,
    write_last_posted_hour,
)


def test_flambe_observation_skips_duplicate_hour(monkeypatch, tmp_path: Path):
    last_path = tmp_path / "last_hour"
    monkeypatch.setenv("CARBON_INTENSITY_LAST_HOUR_PATH", str(last_path))
    write_last_posted_hour("2026-09-29T04:00:00Z")

    posted = {}

    def fake_post(**kwargs):
        posted["called"] = True
        return 99

    monkeypatch.setattr("carbon_intensity.assets.post_observation", fake_post)

    result = flambe_observation(
        {
            "hour_utc": "2026-09-29T04:00:00Z",
            "mean_g_per_kwh": 369.0,
            "unit": "gCO2eq/kWh",
            "timestamp_ms": 1,
            "ba_count": 3,
            "balancing_authorities": [{"ba": "CISO", "g_per_kwh": 300.0}],
            "min_g_per_kwh": 300.0,
            "max_g_per_kwh": 300.0,
            "collected_at": "2026-09-30T04:00:00+00:00",
        }
    )

    assert "called" not in posted
    assert result.metadata["observation_id"] == "skipped_duplicate_hour"
    assert read_last_posted_hour() == "2026-09-29T04:00:00Z"


def test_flambe_observation_posts_and_records_new_hour(monkeypatch, tmp_path: Path):
    last_path = tmp_path / "last_hour"
    monkeypatch.setenv("CARBON_INTENSITY_LAST_HOUR_PATH", str(last_path))
    write_last_posted_hour("2026-09-29T03:00:00Z")

    posted = {}

    def fake_post(**kwargs):
        posted.update(kwargs)
        return 42

    monkeypatch.setattr("carbon_intensity.assets.post_observation", fake_post)

    result = flambe_observation(
        {
            "hour_utc": "2026-09-29T04:00:00Z",
            "mean_g_per_kwh": 370.0,
            "unit": "gCO2eq/kWh",
            "timestamp_ms": 2,
            "ba_count": 3,
            "balancing_authorities": [{"ba": "CISO", "g_per_kwh": 310.0}],
            "min_g_per_kwh": 310.0,
            "max_g_per_kwh": 310.0,
            "collected_at": "2026-09-30T05:00:00+00:00",
        }
    )

    assert posted["value"] == 370.0
    assert posted["timestamp"] == 2
    assert result.metadata["observation_id"] == 42
    assert read_last_posted_hour() == "2026-09-29T04:00:00Z"
