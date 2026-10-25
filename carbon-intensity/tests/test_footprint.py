from copy import deepcopy

import pytest

from carbon_intensity.footprint import FOOD_KWH_DAY, SCOPES, calculate, flambe_metrics
from carbon_intensity.platform import PulsePlatformComponent, publish_result
from carbon_intensity.vehicle import normalize


def snapshot(**overrides):
    return {"date": "2026-10-24", "timezone": "America/Denver", "input_hash": "snapshot-a",
            "profile": {"household_size": 2, "heating": "electric"}, "observations": [], "history": [], **overrides}


def row(scope="ground_travel", quantity=10, **overrides):
    return {"id": "trip", "scope": scope, "quantity": quantity, "unit": "kwh", "basis": "source", "coverage": 1, **overrides}


def category(data, scope="ground_travel"):
    return calculate(data)["categories"][scope]


def test_complete_observations_replace_population_priors_and_zero_is_valid():
    result = category(snapshot(observations=[row(quantity=0)]))
    assert result["source_kwh"] == 0
    assert result["imputed_kwh"] == 0
    assert result["complete_observed"]


def test_partial_observation_replaces_only_its_covered_fraction():
    data = snapshot(profile={"baselines": {"ground_travel": 40}}, observations=[row(quantity=10, coverage=0.25)])
    assert category(data)["source_kwh"] == 40
    assert category(data)["imputed_kwh"] == 30


def test_unknown_coverage_legacy_log_is_a_lower_bound_not_added_on_top_of_default():
    data = snapshot(profile={"baselines": {"ground_travel": 40}}, observations=[row(quantity=10, coverage=0, origin="legacy_log")])
    assert category(data)["source_kwh"] == 40
    data["observations"][0]["quantity"] = 60
    assert category(data)["source_kwh"] == 60


def test_explicit_observation_supersedes_legacy_scope():
    data = snapshot(observations=[row(quantity=20, origin="legacy_log"), row(quantity=5, id="meter")])
    assert category(data)["source_kwh"] == 5


def test_household_and_ev_overlap_does_not_add_baseline_travel():
    data = snapshot(observations=[row("home_electricity", 20, allocation=0.5, basis="electricity"),
                                  row(quantity=5, included_in_scope="home_electricity")])
    result = calculate(data)
    assert result["categories"]["home_electricity"]["source_kwh"] == 28
    assert result["categories"]["ground_travel"]["source_kwh"] == 0
    assert result["excluded_observations"]


def test_missing_compute_is_not_claimed_as_observed_zero():
    result = calculate(snapshot())
    assert "remote_compute" in result["missing_scopes"]
    assert result["status"] == "partial"
    assert result["categories"]["remote_compute"]["method"] == "missing"


def test_history_excludes_future_imputed_and_incomplete_days():
    history = [{"date": day, "scope": "ground_travel", "source_kwh": value, "complete_observed": complete}
               for day, value, complete in [("2026-10-20", 10, True), ("2026-10-21", 20, True),
                                            ("2026-10-22", 30, True), ("2026-10-23", 1000, False),
                                            ("2026-10-25", 1000, True)]]
    result = category(snapshot(history=history))
    assert result["source_kwh"] == 20
    assert result["method"] == "personal_history"


def test_food_prior_excludes_household_transport_and_cooking():
    assert FOOD_KWH_DAY == pytest.approx(18.463855, abs=0.01)
    assert category(snapshot(observations=[row("food", 3, unit="meal")]), "food")["source_kwh"] == pytest.approx(FOOD_KWH_DAY, abs=1e-6)


@pytest.mark.parametrize("value", [-1, float("nan"), float("inf"), True])
def test_invalid_quantities_fail_instead_of_poisoning_score(value):
    with pytest.raises(ValueError):
        calculate(snapshot(observations=[row(quantity=value)]))


def test_custom_factor_requires_traceable_reference():
    with pytest.raises(ValueError, match="source reference"):
        calculate(snapshot(observations=[row("goods", 1, unit="item", factor_kwh_per_unit=25)]))


def test_vehicle_lookup_and_personal_calibration_precedence():
    data = snapshot(profile={"vehicle_id": "123"})
    normalized = normalize(data, fetch=lambda _: {"fuelType1": "Regular Gasoline", "comb08": 30, "year": 2020})
    assert normalized["profile"]["vehicle_kwh_per_km"] == pytest.approx(33.7 / 30 / 1.609344)
    assert "vehicle_kwh_per_km" not in data["profile"]
    data["profile"]["vehicle_kwh_per_km"] = 0.4
    assert normalize(data, fetch=lambda _: pytest.fail("must not fetch"))["profile"]["vehicle_kwh_per_km"] == 0.4


def test_metrics_are_dated_distinct_and_mark_partial_results():
    result = {**calculate(snapshot()), "revision": 2, "calculated_at": "2026-10-25T01:00:00Z"}
    metrics = flambe_metrics(result)
    assert len(metrics) == 5
    assert len({m["kind"] for m in metrics}) == 5
    assert all(m["observed_on"] == "2026-10-24" for m in metrics)
    assert all(m["payload"]["status"] == "partial" for m in metrics)
    assert all(m["kind"] != "carbon" for m in metrics)


def test_failed_delivery_retains_receipts_and_retry_upserts_same_day():
    result = {**calculate(snapshot()), "revision": 2, "calculated_at": "2026-10-25T01:00:00Z", "receipts": {}}
    calls = []
    class API:
        def result(self, _): return deepcopy(result)
        def receipt(self, _, revision, kind, observation_id):
            assert revision == 2
            result["receipts"][kind] = observation_id
    def post(**observation):
        calls.append(observation)
        if len(calls) == 2:
            raise OSError("temporary failure")
        return len(calls)
    with pytest.raises(OSError):
        publish_result(API(), "2026-10-24", post=post)
    assert len(result["receipts"]) == 1
    publish_result(API(), "2026-10-24", post=post)
    assert len(result["receipts"]) == 5
    assert sum(c["kind"] == "pulse_energy" for c in calls) == 1


def test_dirty_result_cannot_publish():
    class API:
        def result(self, _): return {"dirty": True}
    with pytest.raises(RuntimeError, match="recalculate"):
        publish_result(API(), "2026-10-24")


def test_dagster_component_has_separate_refresh_and_delivery_jobs():
    defs = PulsePlatformComponent().build_defs()
    import dagster as dg
    dg.Definitions.validate_loadable(defs)
    names = {s.name for s in defs.schedules}
    assert names == {"pulse_refresh_schedule", "pulse_publish_schedule"}


def test_full_dagster_graph_materializes_saved_result_and_publishes(monkeypatch):
    import carbon_intensity.platform as platform
    import dagster as dg
    stored = {}
    published = []
    class API:
        def inputs(self, day): return snapshot(date=day)
        def save_result(self, result):
            stored.update(result, revision=1, calculated_at="2026-10-25T01:00:00Z", receipts={})
            return deepcopy(stored)
        def result(self, day): return deepcopy(stored)
        def receipt(self, day, revision, kind, observation_id): stored["receipts"][kind] = observation_id
    def post(**observation):
        published.append(observation)
        return len(published)
    original_publish = platform.publish_result
    monkeypatch.setattr(platform, "PulseAPI", API)
    monkeypatch.setattr(platform, "publish_result", lambda api, day: original_publish(api, day, post=post))
    monkeypatch.setenv("PULSE_PUBLISH_ENABLED", "1")
    defs = PulsePlatformComponent().build_defs()
    execution = defs.resolve_job_def("pulse_daily").execute_in_process(partition_key="2026-10-24")
    assert execution.success
    assert len(execution.get_asset_materialization_events()) == 5
    assert len(published) == 5
    assert published[0]["value"] == stored["total_kwh"]
    assert len(stored["receipts"]) == 5


def test_electric_vehicle_source_conversion_applies_once():
    data = snapshot(profile={"vehicle_id": "123", "grid_source_factor": 2.8, "daily_travel_km": 10},
                    observations=[row(quantity=10, unit="km", basis="electricity")])
    normalized = normalize(data, fetch=lambda _: {"fuelType1": "Electricity", "combE": 30})
    expected = 10 * 30 / 100 / 1.609344 * 2.8
    assert category(normalized)["source_kwh"] == pytest.approx(expected, abs=1e-6)
    normalized["observations"] = []
    assert category(normalized)["source_kwh"] == pytest.approx(expected, abs=1e-6)


def test_vehicle_provider_outage_uses_labeled_fallback():
    def unavailable(_): raise OSError("provider unavailable")
    data = normalize(snapshot(profile={"vehicle_id": "123"}), fetch=unavailable)
    assert data["external_factors"]["vehicle"]["status"] == "unavailable"
    assert calculate(data)["categories"]["ground_travel"]["method"] == "population_model"


def test_included_energy_cannot_disappear_through_attribution_cycle():
    with pytest.raises(ValueError, match="cycle"):
        calculate(snapshot(observations=[row("goods", included_in_scope="services"),
                                         row("services", included_in_scope="goods")]))
