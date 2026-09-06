"""Post a generic Flambe observation (same contract as `flambe observe`)."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from typing import Any


class FlambeError(RuntimeError):
    pass


def post_observation(
    *,
    kind: str,
    value: float,
    unit: str | None = None,
    observed_on: str | None = None,
    payload: dict[str, Any] | None = None,
    base_url: str | None = None,
    token: str | None = None,
    opener=None,
) -> int:
    base_url = (base_url or os.environ.get("FLAMBE_URL") or "").rstrip("/")
    token = token or os.environ.get("FLAMBE_API_TOKEN")
    if not base_url or not token:
        raise FlambeError("FLAMBE_URL and FLAMBE_API_TOKEN are required to publish")

    body: dict[str, Any] = {
        "kind": kind,
        "value": value,
        "timestamp_integer": int(time.time() * 1000),
    }
    if unit:
        body["unit"] = unit
    if observed_on:
        body["observed_on"] = observed_on
    if payload:
        body["payload"] = payload

    request = urllib.request.Request(
        f"{base_url}/api/observations",
        data=json.dumps({"observation": body}).encode("utf-8"),
        method="POST",
        headers={
            "authorization": f"Bearer {token}",
            "content-type": "application/json",
            "accept": "application/json",
        },
    )
    reader = opener or urllib.request.urlopen
    try:
        with reader(request, timeout=30) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise FlambeError(f"Flambe observe failed ({error.code}): {detail}") from error

    observation_id = result.get("data", {}).get("id")
    if not isinstance(observation_id, int):
        raise FlambeError(f"unexpected Flambe response: {result}")
    return observation_id
