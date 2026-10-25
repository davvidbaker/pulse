"""Pulse's daily asset graph and custom API integration component."""

import os
from datetime import datetime, timezone

import dagster as dg

from carbon_intensity.flambe import post_observation
from carbon_intensity.footprint import calculate, flambe_metrics
from carbon_intensity.pulse_api import PulseAPI
from carbon_intensity.vehicle import normalize

PARTITIONS = dg.DailyPartitionsDefinition(start_date="2020-01-01", end_offset=1)
RETRY = dg.RetryPolicy(max_retries=3, delay=15)


def publish_result(api, day, post=post_observation):
    # Read the current persisted revision, never a stale asset IO-manager copy.
    result = api.result(day)
    if result.get("dirty"):
        raise RuntimeError("Pulse inputs changed; recalculate before publishing")
    receipts = result.get("receipts", {})
    for observation in flambe_metrics(result):
        kind = observation["kind"]
        if kind in receipts:
            continue
        observation_id = post(**observation)
        # A failed ack is safe to retry: Flambe upserts kind + local day.
        api.receipt(day, result["revision"], kind, observation_id)
    return result["revision"]


class PulsePlatformComponent(dg.Component):
    """Orchestrate Pulse's custom scoped API without fetching data at definition load."""

    def build_defs(self, context=None):
        @dg.asset(key="pulse_input_snapshot", group_name="pulse", partitions_def=PARTITIONS, retry_policy=RETRY)
        def inputs(context: dg.AssetExecutionContext) -> dict:
            return PulseAPI().inputs(context.partition_key)

        @dg.asset(key="pulse_normalized_inputs", group_name="pulse", partitions_def=PARTITIONS, retry_policy=RETRY)
        def normalized(pulse_input_snapshot: dict) -> dict:
            return normalize(pulse_input_snapshot)

        @dg.asset(key="pulse_daily_footprint", group_name="pulse", partitions_def=PARTITIONS, retry_policy=RETRY)
        def footprint(pulse_normalized_inputs: dict) -> dict:
            return calculate(pulse_normalized_inputs)

        @dg.asset(key="pulse_daily_result", group_name="pulse", partitions_def=PARTITIONS, retry_policy=RETRY)
        def stored(pulse_daily_footprint: dict) -> dict:
            return PulseAPI().save_result(pulse_daily_footprint)

        @dg.asset(key="pulse_flambe_delivery", group_name="pulse", partitions_def=PARTITIONS,
                  deps=[stored], retry_policy=RETRY)
        def delivery(context: dg.AssetExecutionContext) -> dg.MaterializeResult:
            if os.environ.get("PULSE_PUBLISH_ENABLED") != "1":
                return dg.MaterializeResult(metadata={"delivery": "disabled; result retained in Pulse"})
            revision = publish_result(PulseAPI(), context.partition_key)
            return dg.MaterializeResult(metadata={"revision": revision, "delivery": "acknowledged"})

        job = dg.define_asset_job("pulse_daily", selection=dg.AssetSelection.groups("pulse"),
                                  executor_def=dg.in_process_executor,
                                  tags={"pulse/platform": "true"})
        refresh_job = dg.define_asset_job("pulse_refresh", selection=dg.AssetSelection.assets(inputs, normalized, footprint, stored),
                                          executor_def=dg.in_process_executor,
                                          tags={"pulse/platform": "true"})
        publish_job = dg.define_asset_job("pulse_publish", selection=dg.AssetSelection.assets(delivery),
                                          executor_def=dg.in_process_executor,
                                          tags={"pulse/platform": "true"})

        def requests(context):
            if not os.environ.get("PULSE_URL") or not os.environ.get("PULSE_PLATFORM_TOKEN"):
                return dg.SkipReason("Pulse platform API is not configured")
            tick = context.scheduled_execution_time or datetime.now(timezone.utc)
            return [dg.RunRequest(run_key=f"{tick.isoformat()}:{day}", partition_key=day)
                    for day in PulseAPI().work()]

        refresh = dg.schedule(name="pulse_refresh_schedule", job=refresh_job, cron_schedule="*/5 * * * *",
                              default_status=dg.DefaultScheduleStatus.RUNNING)(requests)
        publish = dg.schedule(name="pulse_publish_schedule", job=publish_job, cron_schedule="10 * * * *",
                              default_status=dg.DefaultScheduleStatus.RUNNING)(requests)
        return dg.Definitions(assets=[inputs, normalized, footprint, stored, delivery],
                              jobs=[job, refresh_job, publish_job], schedules=[refresh, publish])
