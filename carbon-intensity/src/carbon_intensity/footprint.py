"""Pure daily energy model; scenario ranges are not confidence intervals."""
from __future__ import annotations

from collections import defaultdict
from datetime import date
from math import isfinite
from statistics import median

VERSION = "pulse-energy-v1"
SCOPES = ("home_electricity", "home_heating", "ground_travel", "food",
          "remote_compute", "flights", "goods", "services")
FOOD_SOURCE = "https://www.ers.usda.gov/data-products/resource-requirements-of-food-demand"
HOME_SOURCE = "https://www.eia.gov/energyexplained/use-of-energy/electricity-use-in-homes.php"
TRAVEL_SOURCE = "https://www.fhwa.dot.gov/policyinformation/pubs/our_nations_highways_2026/drivers.cfm"
SOURCE_CONVENTION = "https://www.energystar.gov/sites/default/files/asset/document/BPS-White_paper_final.pdf"
# USDA RRFD 2023 Xf0000, TOTAL, release 2026-03-17, billion Btu/year.
# Exclude stages 15 (shopping transport), 16 (equipment), 17 (kitchen utilities).
# Census vintage-2023 population: 334,914,895; billion Btu to kWh: 293071.07.
FOOD_KWH_DAY = (10144929.951 - 836028.356 - 289471.150 - 1318109.168) * 293071.07 / 334914895 / 365


def number(value, *, minimum=0.0, maximum=None):
    if isinstance(value, bool):
        raise ValueError("boolean is not an energy quantity")
    result = float(value)
    if not isfinite(result) or result < minimum or (maximum is not None and result > maximum):
        raise ValueError("quantity outside its allowed range")
    return result


def baseline(scope, profile, history, day):
    observed = [r for r in history if r["scope"] == scope and r.get("complete_observed")
                and 0 < (day - date.fromisoformat(r["date"])).days <= 28]
    same_weekday = [r for r in observed if date.fromisoformat(r["date"]).weekday() == day.weekday()]
    selected = same_weekday if len(same_weekday) >= 3 else observed
    if len(selected) >= 3:
        return median(number(r["source_kwh"]) for r in selected), "personal_history", "complete observed days, trailing 28 days"
    custom = profile.get("baselines", {}).get(scope)
    if custom is not None:
        return number(custom), "personal_baseline", "user supplied source kWh/day"
    household = number(profile.get("household_size", 2.5), minimum=1)
    grid = number(profile.get("grid_source_factor", 2.8), minimum=1)
    if scope == "home_electricity":
        return 10500 / 365 / household * grid, "population_model", HOME_SOURCE
    if scope == "home_heating":
        if profile.get("heating") in ("electric", "none"):
            return 0.0, "included_elsewhere", "electric heating included in household electricity, or user declares none"
        if profile.get("heating") == "gas":
            return 56.6 * 293.07107 / 365 / household * 1.05, "population_model", "https://www.eia.gov/todayinenergy/detail.php?id=57321"
    if scope == "ground_travel":
        if profile.get("drives", True) is False:
            return None
        km = number(profile.get("daily_travel_km", 13735 * 1.609344 / 365))
        efficiency = number(profile.get("vehicle_kwh_per_km", 0.7))
        multiplier = number(profile.get("grid_source_factor", 2.8), minimum=1) if profile.get("vehicle_energy_basis") == "electricity" else 1
        return km * efficiency * multiplier, "population_model", profile.get("vehicle_factor_ref", TRAVEL_SOURCE) + " ; 0.7 fuel kWh/km is a configurable vehicle proxy"
    if scope == "food":
        return FOOD_KWH_DAY, "population_model", FOOD_SOURCE
    return None


def observation_energy(row, profile):
    scope, unit = row["scope"], row["unit"]
    quantity = number(row["quantity"])
    factor = row.get("factor_kwh_per_unit")
    if factor is not None:
        if not row.get("source_ref"):
            raise ValueError("custom energy factors require a source reference")
        factor = number(factor)
    elif unit == "kwh":
        factor = 1.0
    elif scope == "ground_travel" and unit == "km":
        factor = number(profile.get("vehicle_kwh_per_km", 0.7))
    elif scope == "ground_travel" and unit == "liter":
        factor = 10.7 if row.get("fuel_type") == "diesel" else 9.7
    elif scope == "home_heating" and unit == "therm":
        factor = 29.307107
    elif scope == "food" and unit == "meal":
        factor = FOOD_KWH_DAY / 3
    else:
        raise ValueError(f"an energy factor is required for {scope}/{unit}")
    basis = row.get("basis", "source")
    if row.get("factor_kwh_per_unit") is None:
        if scope == "ground_travel" and unit == "km":
            basis = profile.get("vehicle_energy_basis", "fuel")
        elif unit == "meal":
            basis = "source"
        elif unit == "therm":
            basis = "gas"
        elif unit == "liter":
            basis = "fuel"
    multiplier = {"source": 1.0, "electricity": number(profile.get("grid_source_factor", 2.8), minimum=1),
                  "gas": 1.05, "fuel": 1.0}.get(basis)
    if multiplier is None:
        raise ValueError("unknown energy basis")
    return quantity * factor * multiplier * number(row.get("allocation", 1), maximum=1)


def calculate(snapshot):
    day = date.fromisoformat(snapshot["date"])
    profile = snapshot.get("profile", {})
    rows, included, excluded = defaultdict(list), defaultdict(list), []
    for row in snapshot.get("observations", []):
        if row["scope"] not in SCOPES:
            raise ValueError("unknown footprint scope")
        if row.get("included_in_scope"):
            if row["included_in_scope"] not in SCOPES or row["included_in_scope"] == row["scope"]:
                raise ValueError("invalid included-in scope")
            included[row["scope"]].append(row)
            excluded.append({"id": row["id"], "scope": row["scope"], "included_in_scope": row["included_in_scope"]})
        else:
            rows[row["scope"]].append(row)
    # Reject attribution cycles: energy cannot disappear through A-in-B-in-A declarations.
    edges = defaultdict(set)
    for item in excluded:
        edges[item["scope"]].add(item["included_in_scope"])
    def check_cycle(scope, path):
        if scope in path:
            raise ValueError("included energy attribution contains a cycle")
        for target in edges[scope]:
            check_cycle(target, path | {scope})
    for scope in SCOPES:
        check_cycle(scope, set())
    categories = {}
    for scope in SCOPES:
        candidates = rows[scope]
        explicit = [r for r in candidates if r.get("origin") != "legacy_log"]
        chosen = explicit or candidates
        value = sum(observation_energy(r, profile) for r in chosen)
        coverage = max((number(r.get("coverage", 1), maximum=1) for r in chosen + included[scope]), default=0)
        prior = baseline(scope, profile, snapshot.get("history", []), day)
        missing = coverage < 1 and prior is None
        imputed = (max(0.0, prior[0] - value) if coverage == 0 else (1 - coverage) * prior[0]) if prior else 0.0
        categories[scope] = {
            "source_kwh": round(value + imputed, 6), "observed_kwh": round(value, 6),
            "imputed_kwh": round(imputed, 6), "coverage": coverage,
            "complete_observed": coverage == 1 and bool(chosen),
            "lower_kwh": round(value * 0.8 + imputed * 0.5, 6),
            "upper_kwh": round(value * 1.2 + imputed * 1.5, 6),
            "missing": missing, "method": ("included_elsewhere" if included[scope] and not chosen else "observations") if coverage == 1 else (prior[1] if prior else "missing"),
            "source_ref": prior[2] if prior and coverage < 1 else None,
            "observation_ids": [r["id"] for r in chosen],
            "factors": [{"id": r["id"], "unit": r["unit"], "quantity": r["quantity"],
                         "basis": r.get("basis", "source"), "source_ref": r.get("source_ref"),
                         "quality": r.get("quality", "estimated"),
                         "source_kwh": round(observation_energy(r, profile), 6)} for r in chosen],
        }
    total = sum(c["source_kwh"] for c in categories.values())
    missing = [s for s, c in categories.items() if c["missing"]]
    observed = sum(c["observed_kwh"] for c in categories.values())
    return {
        "date": snapshot["date"], "timezone": snapshot["timezone"], "input_hash": snapshot["input_hash"],
        "methodology_version": VERSION, "energy_basis": "source_equivalent",
        "total_kwh": round(total, 6), "lower_kwh": round(sum(c["lower_kwh"] for c in categories.values()), 6),
        "upper_kwh": round(sum(c["upper_kwh"] for c in categories.values()), 6),
        "observed_fraction": round(observed / total, 6) if total else 0,
        "status": "partial" if missing else "estimated", "missing_scopes": missing,
        "categories": categories, "excluded_observations": excluded,
        "range_method": "scenario envelope; not a statistical confidence interval",
        "source_convention": SOURCE_CONVENTION, "external_factors": snapshot.get("external_factors", {}),
    }


def flambe_metrics(result):
    payload = {k: result[k] for k in ("timezone", "methodology_version", "energy_basis", "status", "missing_scopes",
                                    "lower_kwh", "upper_kwh", "observed_fraction", "input_hash")}
    payload.update(source="pulse", revision=result["revision"], categories=result["categories"],
                   calculated_at=result["calculated_at"])
    metrics = [{"kind": "pulse_energy", "value": result["total_kwh"], "unit": "kWh"}]
    metrics.extend([
        {"kind": "pulse_energy_lower", "value": result["lower_kwh"], "unit": "kWh"},
        {"kind": "pulse_energy_upper", "value": result["upper_kwh"], "unit": "kWh"},
        {"kind": "pulse_scope_coverage", "value": (len(SCOPES) - len(result["missing_scopes"])) / len(SCOPES), "unit": "fraction"},
    ])
    metrics.append({"kind": "pulse_observed_fraction", "value": result["observed_fraction"], "unit": "fraction"})
    return [{**m, "observed_on": result["date"], "payload": payload} for m in metrics]
