import dagster as dg

from pulse_carbon.assets import daily_carbon_schedule


def test_daily_carbon_schedule_starts_running_at_1800_utc():
    assert daily_carbon_schedule.name == "daily_us_carbon_schedule"
    assert daily_carbon_schedule.cron_schedule == "0 18 * * *"
    assert daily_carbon_schedule.execution_timezone == "UTC"
    assert daily_carbon_schedule.default_status == dg.DefaultScheduleStatus.RUNNING
