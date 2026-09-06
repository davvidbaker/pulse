import json

from pulse_carbon.flambe import post_observation


class FakeResponse:
    def __init__(self, payload: dict, status: int = 201):
        self.status = status
        self._payload = json.dumps(payload).encode("utf-8")

    def read(self):
        return self._payload

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def test_post_observation_hits_flambe_api():
    captured = {}

    def opener(request, timeout=30):
        captured["url"] = request.full_url
        captured["body"] = json.loads(request.data.decode("utf-8"))
        captured["authorization"] = request.get_header("Authorization")
        return FakeResponse({"data": {"id": 42}})

    observation_id = post_observation(
        kind="carbon",
        value=200.0,
        unit="gCO2eq/kWh",
        observed_on="2026-09-03",
        payload={"source": "us-ba-mean"},
        base_url="http://localhost:4001/",
        token="flb_test",
        opener=opener,
    )

    assert observation_id == 42
    assert captured["url"] == "http://localhost:4001/api/observations"
    assert captured["authorization"] == "Bearer flb_test"
    assert captured["body"]["observation"]["kind"] == "carbon"
    assert captured["body"]["observation"]["observed_on"] == "2026-09-03"
    assert captured["body"]["observation"]["payload"]["source"] == "us-ba-mean"
