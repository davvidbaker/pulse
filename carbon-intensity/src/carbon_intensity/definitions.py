import dagster as dg

from carbon_intensity.assets import (
    carbon_intensity_job,
    carbon_intensity_schedule,
    flambe_observation,
    generation_observation,
    grid_market_data_job,
    grid_market_data_schedule,
    hourly_generation,
    hourly_hub_prices,
    hub_price_observation,
    us_grid_intensity,
)

defs = dg.Definitions(
    assets=[
        us_grid_intensity,
        flambe_observation,
        hourly_generation,
        generation_observation,
        hourly_hub_prices,
        hub_price_observation,
    ],
    jobs=[carbon_intensity_job, grid_market_data_job],
    schedules=[carbon_intensity_schedule, grid_market_data_schedule],
)
