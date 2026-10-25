import time

import dagster as dg
from dagster._core.remote_origin import RegisteredCodeLocationOrigin, RemoteJobOrigin, RemoteRepositoryOrigin

from carbon_intensity.recovery import recover_interrupted_runs


@dg.job
def empty_job():
    pass


def test_recovery_releases_lost_workers_but_preserves_queue_and_new_workers():
    with dg.DagsterInstance.ephemeral() as instance:
        lost = [instance.create_run_for_job(empty_job, status=status)
                for status in [dg.DagsterRunStatus.STARTED, dg.DagsterRunStatus.STARTING]]
        canceling = instance.create_run_for_job(empty_job, status=dg.DagsterRunStatus.CANCELING)
        origin = RemoteRepositoryOrigin(RegisteredCodeLocationOrigin("test"), "__repository__")
        queued = instance.create_run_for_job(
            empty_job, status=dg.DagsterRunStatus.QUEUED,
            remote_job_origin=RemoteJobOrigin(origin, "empty_job"))
        boot = time.time()
        current = instance.create_run_for_job(empty_job, status=dg.DagsterRunStatus.STARTED)

        assert set(recover_interrupted_runs(instance, boot)) == {r.run_id for r in lost + [canceling]}
        assert all(instance.get_run_by_id(r.run_id).status == dg.DagsterRunStatus.FAILURE for r in lost)
        assert instance.get_run_by_id(canceling.run_id).status == dg.DagsterRunStatus.CANCELED
        assert instance.get_run_by_id(queued.run_id).status == dg.DagsterRunStatus.QUEUED
        assert instance.get_run_by_id(current.run_id).status == dg.DagsterRunStatus.STARTED
        assert recover_interrupted_runs(instance, boot) == []
