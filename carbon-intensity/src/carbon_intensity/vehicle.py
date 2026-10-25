"""Optional model/year calibration from the official FuelEconomy.gov record."""
from __future__ import annotations

from copy import deepcopy
from functools import lru_cache
import json
from urllib.request import Request, urlopen


@lru_cache(maxsize=128)
def vehicle_record(vehicle_id):
    if not str(vehicle_id).isdigit():
        raise ValueError("invalid vehicle ID")
    request = Request(f"https://www.fueleconomy.gov/ws/rest/vehicle/{vehicle_id}",
                      headers={"accept": "application/json"})
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read())


def normalize(snapshot, fetch=vehicle_record):
    normalized = deepcopy(snapshot)
    profile = normalized["profile"]
    vehicle_id = profile.get("vehicle_id")
    if not vehicle_id or profile.get("vehicle_kwh_per_km") is not None:
        return normalized
    # Explicit personal calibration wins; this lookup fills only absent efficiency.
    try:
        record = fetch(vehicle_id)
    except OSError:
        normalized["external_factors"] = {"vehicle": {"id": str(vehicle_id), "status": "unavailable",
                                                       "fallback": "personal history or generic vehicle proxy"}}
        return normalized
    if record.get("fuelType1") == "Electricity":
        energy = float(record["combE"]) / 100 / 1.609344
        basis = "electricity"
    elif str(record.get("fuelType1", "")).lower() in ("regular gasoline", "premium gasoline", "midgrade gasoline", "diesel"):
        density = 38.0 if str(record["fuelType1"]).lower() == "diesel" else 33.7
        energy = density / float(record["comb08"]) / 1.609344
        basis = "fuel"
    else:
        raise ValueError("vehicle needs a personal energy calibration for this fuel mix")
    if energy <= 0:
        raise ValueError("vehicle energy record must be positive")
    profile["vehicle_kwh_per_km"] = energy
    profile["vehicle_energy_basis"] = basis
    profile["vehicle_factor_ref"] = f"https://www.fueleconomy.gov/ws/rest/vehicle/{vehicle_id}"
    normalized["external_factors"] = {"vehicle": {
        "id": str(vehicle_id), "year": record.get("year"), "make": record.get("make"),
        "model": record.get("model"), "kwh_per_km": energy, "basis": basis,
        "source": profile["vehicle_factor_ref"],
    }}
    return normalized
