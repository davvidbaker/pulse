import dagster as dg

from carbon_intensity.assets import (
    carbon_intensity_job,
    carbon_intensity_schedule,
    flambe_observation,
    us_grid_intensity,
)

defs = dg.Definitions(
    assets=[us_grid_intensity, flambe_observation],
    jobs=[carbon_intensity_job],
    schedules=[carbon_intensity_schedule],
)
