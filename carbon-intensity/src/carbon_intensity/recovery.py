"""Recover runs whose local workers were lost when this single VM rebooted."""

from dagster import DagsterInstance, DagsterRunStatus, RunsFilter


def recover_interrupted_runs(instance, boot_time):
    active = [DagsterRunStatus.STARTING, DagsterRunStatus.STARTED, DagsterRunStatus.CANCELING]
    recovered = []
    for record in instance.get_run_records(filters=RunsFilter(statuses=active)):
        started = record.start_time or record.create_timestamp.timestamp()
        if started >= boot_time:
            continue
        run = record.dagster_run
        message = "Local run worker was interrupted by a VM restart."
        if run.status == DagsterRunStatus.CANCELING:
            instance.report_run_canceled(run, message)
        else:
            instance.report_run_failed(run, message)
        recovered.append(run.run_id)
    return recovered


if __name__ == "__main__":
    with open("/proc/stat") as stat:
        boot = next(float(line.split()[1]) for line in stat if line.startswith("btime "))
    with DagsterInstance.get() as instance:
        print(f"Recovered {len(recover_interrupted_runs(instance, boot))} interrupted runs")
