"""Scoped Pulse API; never put credentials or response bodies into error logs."""
from __future__ import annotations

import json
import os
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


class PulseAPI:
    def __init__(self, base_url=None, token=None, opener=None):
        self.base_url = (base_url or os.environ.get("PULSE_URL", "")).rstrip("/")
        self.token = token or os.environ.get("PULSE_PLATFORM_TOKEN", "")
        parsed = urlparse(self.base_url)
        if not self.token or parsed.scheme not in ("https", "http") or not parsed.hostname:
            raise ValueError("PULSE_URL and PULSE_PLATFORM_TOKEN are required")
        if parsed.scheme == "http" and parsed.hostname not in ("localhost", "127.0.0.1", "::1"):
            raise ValueError("remote Pulse API requires HTTPS")
        self.opener = opener or urlopen

    def request(self, method, path, data=None):
        request = Request(self.base_url + "/api/platform" + path,
                          data=json.dumps(data, allow_nan=False).encode() if data is not None else None,
                          method=method, headers={"authorization": "Bearer " + self.token,
                                                  "content-type": "application/json", "accept": "application/json"})
        try:
            with self.opener(request, timeout=30) as response:
                return json.loads(response.read())
        except HTTPError as error:
            raise RuntimeError(f"Pulse API {method} {path} failed: HTTP {error.code}") from None

    def work(self):
        return self.request("GET", "/work")["dates"]

    def inputs(self, day):
        return self.request("GET", f"/inputs/{day}")

    def save_result(self, result):
        return self.request("PUT", f"/results/{result['date']}", result)

    def result(self, day):
        return self.request("GET", f"/results/{day}")

    def receipt(self, day, revision, kind, observation_id):
        return self.request("POST", f"/results/{day}/receipts",
                            {"revision": revision, "kind": kind, "observation_id": observation_id})
