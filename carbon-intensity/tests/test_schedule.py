import dagster as dg

from carbon_intensity.assets import carbon_intensity_schedule


def test_carbon_intensity_schedule_starts_running_hourly_utc():
    assert carbon_intensity_schedule.name == "carbon_intensity_schedule"
    assert carbon_intensity_schedule.cron_schedule == "0 * * * *"
    assert carbon_intensity_schedule.execution_timezone == "UTC"
    assert carbon_intensity_schedule.default_status == dg.DefaultScheduleStatus.RUNNING
