import dagster as dg

from pulse_carbon.assets import (
    daily_carbon_job,
    daily_carbon_schedule,
    flambe_carbon_observation,
    us_grid_intensity,
)

defs = dg.Definitions(
    assets=[us_grid_intensity, flambe_carbon_observation],
    jobs=[daily_carbon_job],
    schedules=[daily_carbon_schedule],
)
