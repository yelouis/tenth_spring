#!/usr/bin/env python3
"""
tools/check_famous_places.py — Validate game/config/famous_places.json
Contract: docs/implementation_plan_famous_places.md §1 & §8.1, docs/design_famous_places.md §6 & §9
"""

import json
import os
import re
import sys

REGIONS = [
    "New England",
    "Middle Atlantic",
    "South Atlantic",
    "East South Central",
    "West South Central",
    "East North Central",
    "West North Central",
    "Mountain",
    "Pacific",
]

US_LAT_MIN = 18.0
US_LAT_MAX = 72.0
US_LON_MIN = -180.0
US_LON_MAX = -65.0

KEY_PURPOSES = {"T", "W", "L", "Q"}
VALID_PURPOSES = {"T", "W", "L", "H", "P", "Q", "R", "M"}

VALID_REQUIRES_KEYS = {
    "dex_all",
    "dex_any",
    "item",
    "flag",
    "quest",
    "cells",
    "gears",
    "anchors",
    "hollow_wins",
    "zones_cleansed",
}

def check_coords(lat, lon, label):
    if not (US_LAT_MIN <= lat <= US_LAT_MAX):
        raise ValueError(f"{label} lat {lat} out of US bounds [{US_LAT_MIN}, {US_LAT_MAX}]")
    if not (US_LON_MIN <= lon <= US_LON_MAX):
        raise ValueError(f"{label} lon {lon} out of US bounds [{US_LON_MIN}, {US_LON_MAX}]")

def validate_famous_places(config_path):
    if not os.path.isfile(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        places = json.load(f)

    if not isinstance(places, list):
        raise ValueError("Root element must be a list of places")

    if len(places) != 105:
        raise ValueError(f"Expected exactly 105 entries, got {len(places)}")

    cities_by_region = {r: [] for r in REGIONS}
    legendaries_by_region = {r: [] for r in REGIONS}
    city_ids = set()
    site_ids = set()
    spot_ids = set()
    legendary_dex_set = set()
    wardens_by_region = {r: [] for r in REGIONS}
    requires_by_dex = {}

    for p in places:
        pid = p.get("id", "")
        kind = p.get("kind", "")
        name = p.get("name", "")
        region = p.get("region", "")

        if not pid or not kind or not name or not region:
            raise ValueError(f"Place missing core fields: {p}")

        if region not in REGIONS:
            raise ValueError(f"Place {pid} has invalid region '{region}'")

        if kind == "city":
            city_ids.add(pid)
            cities_by_region[region].append(p)

            # Boundary
            b = p.get("osm_boundary", "")
            if not re.match(r"^r\d+$", str(b)):
                raise ValueError(f"City {pid} invalid osm_boundary: {b}")

            # Waypost
            wp = p.get("waypost", {})
            if not wp or not wp.get("name"):
                raise ValueError(f"City {pid} missing waypost name")
            check_coords(float(wp["lat"]), float(wp["lon"]), f"City {pid} waypost")

            # Warden (optional per city, but 1 per region)
            if "warden" in p:
                w = p["warden"]
                if not w.get("name") or not w.get("type") or not w.get("landmark"):
                    raise ValueError(f"City {pid} invalid warden: {w}")
                lm = w["landmark"]
                if not lm.get("name"):
                    raise ValueError(f"City {pid} warden landmark missing name")
                check_coords(float(lm["lat"]), float(lm["lon"]), f"City {pid} warden landmark")
                wardens_by_region[region].append(w)

            # Interiors: at least 2 interiors
            interiors = p.get("interiors", [])
            if len(interiors) < 2:
                raise ValueError(f"City {pid} has {len(interiors)} interiors, expected >= 2")

            for item in interiors:
                iid = item.get("id", "")
                iname = item.get("name", "")
                fam = item.get("family", "")
                purp = item.get("purposes", "")
                door = item.get("door", {})
                if not iid or not iname or not fam or not purp or not door:
                    raise ValueError(f"City {pid} interior invalid: {item}")
                check_coords(float(door["lat"]), float(door["lon"]), f"City {pid} interior {iid}")

                # Purposes: at least 2 purposes, at least one of T, W, L, Q
                purp_tokens = set(purp.split())
                if len(purp_tokens) < 2:
                    raise ValueError(f"Interior {iid} has < 2 purposes: {purp}")
                if not (purp_tokens & KEY_PURPOSES):
                    raise ValueError(f"Interior {iid} lacks key purpose (T, W, L, Q): {purp}")
                if not purp_tokens.issubset(VALID_PURPOSES):
                    raise ValueError(f"Interior {iid} has unknown purpose: {purp_tokens - VALID_PURPOSES}")

        elif kind == "site":
            site_ids.add(pid)
            b = p.get("osm_boundary", "")
            if not re.match(r"^[rw]\d+$", str(b)):
                raise ValueError(f"Site {pid} invalid osm_boundary: {b}")

            wp = p.get("waypost", {})
            if not wp or not wp.get("name"):
                raise ValueError(f"Site {pid} missing waypost")
            check_coords(float(wp["lat"]), float(wp["lon"]), f"Site {pid} waypost")

            # Legendary dex
            dex = p.get("legendary_dex")
            if not isinstance(dex, int) or dex <= 0:
                raise ValueError(f"Site {pid} missing valid legendary_dex: {dex}")
            if dex in legendary_dex_set:
                raise ValueError(f"Duplicate legendary dex {dex} on site {pid}")
            legendary_dex_set.add(dex)
            legendaries_by_region[region].append(dex)
            if "requires" in p:
                requires_by_dex[dex] = (pid, p["requires"])

            # Visitor centre interior
            interiors = p.get("interiors", [])
            if not interiors:
                raise ValueError(f"Site {pid} missing interiors (expected visitor centre)")
            has_vc = any("visitor centre" in i.get("name", "").lower() or "visitor center" in i.get("name", "").lower() or i.get("family") == "hall" for i in interiors)
            if not has_vc:
                raise ValueError(f"Site {pid} lacks visitor centre interior")

            for item in interiors:
                iid = item.get("id", "")
                iname = item.get("name", "")
                fam = item.get("family", "")
                purp = item.get("purposes", "")
                door = item.get("door", {})
                if not iid or not iname or not fam or not purp or not door:
                    raise ValueError(f"Site {pid} interior invalid: {item}")
                check_coords(float(door["lat"]), float(door["lon"]), f"Site {pid} interior {iid}")
                purp_tokens = set(purp.split())
                if len(purp_tokens) < 2:
                    raise ValueError(f"Interior {iid} has < 2 purposes: {purp}")
                if not (purp_tokens & KEY_PURPOSES):
                    raise ValueError(f"Interior {iid} lacks key purpose (T, W, L, Q): {purp}")
                if not purp_tokens.issubset(VALID_PURPOSES):
                    raise ValueError(f"Interior {iid} has unknown purpose: {purp_tokens - VALID_PURPOSES}")

        elif kind == "spot":
            spot_ids.add(pid)
            target_city = p.get("city", "")
            if not target_city:
                raise ValueError(f"Spot {pid} missing 'city' field")

            dex = p.get("legendary_dex")
            if not isinstance(dex, int) or dex <= 0:
                raise ValueError(f"Spot {pid} missing valid legendary_dex: {dex}")
            if dex in legendary_dex_set:
                raise ValueError(f"Duplicate legendary dex {dex} on spot {pid}")
            legendary_dex_set.add(dex)
            legendaries_by_region[region].append(dex)
            if "requires" in p:
                requires_by_dex[dex] = (pid, p["requires"])
        else:
            raise ValueError(f"Unknown kind '{kind}' for place {pid}")

    # Validate city counts (exactly 3 per region, 27 total)
    for r, clist in cities_by_region.items():
        if len(clist) != 3:
            raise ValueError(f"Region '{r}' has {len(clist)} cities (expected 3)")
    if len(city_ids) != 27:
        raise ValueError(f"Expected 27 cities, got {len(city_ids)}")

    # Validate site count (60) and spot count (18)
    if len(site_ids) != 60:
        raise ValueError(f"Expected 60 sites, got {len(site_ids)}")
    if len(spot_ids) != 18:
        raise ValueError(f"Expected 18 spots, got {len(spot_ids)}")

    # Validate legendary count (78) and 7–9 per region
    if len(legendary_dex_set) != 78:
        raise ValueError(f"Expected 78 distinct legendaries, got {len(legendary_dex_set)}")
    for r, llist in legendaries_by_region.items():
        if not (7 <= len(llist) <= 9):
            raise ValueError(f"Region '{r}' has {len(llist)} legendaries (expected 7–9)")

    # Validate spots name an existing city
    for p in places:
        if p.get("kind") == "spot":
            c = p.get("city")
            if c not in city_ids:
                raise ValueError(f"Spot {p.get('id')} references non-existent city '{c}'")

    # Validate exactly one warden per region
    for r, wlist in wardens_by_region.items():
        if len(wlist) != 1:
            raise ValueError(f"Region '{r}' has {len(wlist)} Wardens (expected 1)")

    # Validate requires clauses (every key is one of §9's keys, every referenced dex is in the file, and no circular chains)
    for dex, (pid, req) in requires_by_dex.items():
        if not isinstance(req, dict) or not req:
            raise ValueError(f"Place {pid} has invalid requires object: {req}")
        for k, v in req.items():
            if k not in VALID_REQUIRES_KEYS:
                raise ValueError(f"Place {pid} has unknown requires key '{k}'")
            if k in ("dex_all", "dex_any"):
                if not isinstance(v, list) or not v:
                    raise ValueError(f"Place {pid} requires '{k}' must be a non-empty list")
                for ref_dex in v:
                    if not isinstance(ref_dex, int) or ref_dex not in legendary_dex_set:
                        raise ValueError(f"Place {pid} requires non-legendary dex {ref_dex}")
            elif k in ("item", "flag", "quest"):
                if not isinstance(v, str) or not v:
                    raise ValueError(f"Place {pid} requires '{k}' must be a non-empty string")
            elif k in ("cells", "gears", "anchors", "hollow_wins", "zones_cleansed"):
                if not isinstance(v, int) or v <= 0:
                    raise ValueError(f"Place {pid} requires '{k}' must be a positive int")

    # Check reachability / no circular dependency chains among legendary dex requirements
    reachable = set()
    for dex in legendary_dex_set:
        if dex not in requires_by_dex:
            reachable.add(dex)
        else:
            _, req = requires_by_dex[dex]
            if "dex_all" not in req and "dex_any" not in req:
                reachable.add(dex)

    changed = True
    while changed:
        changed = False
        for dex, (pid, req) in requires_by_dex.items():
            if dex in reachable:
                continue
            ok_all = True
            if "dex_all" in req:
                ok_all = all(d in reachable for d in req["dex_all"])
            ok_any = True
            if "dex_any" in req:
                ok_any = any(d in reachable for d in req["dex_any"])
            if ok_all and ok_any:
                reachable.add(dex)
                changed = True

    if len(reachable) != len(legendary_dex_set):
        unreachable = sorted(legendary_dex_set - reachable)
        raise ValueError(f"Circular or unreachable legendary dex chain: {unreachable}")

    return True

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config_path = os.path.join(repo_root, "game", "config", "famous_places.json")

    if len(sys.argv) > 1:
        config_path = sys.argv[1]

    try:
        validate_famous_places(config_path)
        print(f"[CHECK FAMOUS PLACES OK] Validated {config_path}: 27 cities, 60 sites, 18 spots, 78 legendaries, 9 wardens.")
        sys.exit(0)
    except Exception as e:
        print(f"[FAIL] {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
