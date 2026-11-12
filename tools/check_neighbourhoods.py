#!/usr/bin/env python3
"""
tools/check_neighbourhoods.py — Validate game/config/neighbourhoods.json (Item 47)
Contract: docs/implementation_plan_dc_trial.md §1.4, docs/design_neighbourhoods_and_caricature.md §2–§7
"""

import collections
import gzip
import json
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

import grid  # noqa: E402

VALID_ZONES = {
    "cemetery",
    "hospital",
    "ruins",
    "waterfront",
    "institutional",
    "retail",
    "downtown",
    "industrial",
    "parkland",
    "residential",
    "wilds",
}

VALID_HAUNT_SITES = {"", "cemetery", "ruins", "hospital"}
VALID_RUIN_LEVELS = {"camp", "near", "mid", "far"}
VALID_ROLES = {"gateway", "inner", "finale"}
VALID_SOURCES = {"roster", "lair", "new"}
VALID_NEW_PATTERNS = {
    "keeper",
    "haunting",
    "switches",
    "escort",
    "show",
    "delivery",
    "famous_building",
}


class RuleError(Exception):
    def __init__(self, rule_id: str, message: str):
        super().__init__(f"{rule_id}: {message}")
        self.rule_id = rule_id
        self.message = message


def _is_int(val) -> bool:
    return isinstance(val, int) and not isinstance(val, bool)


def _is_num(val) -> bool:
    return isinstance(val, (int, float)) and not isinstance(val, bool)


def _is_nonempty_str(val) -> bool:
    return isinstance(val, str) and len(val.strip()) > 0


def _load_pack_cells_by_city(pack_path: str) -> dict:
    with gzip.open(pack_path, "rt", encoding="utf-8") as f:
        pack = json.load(f)
    cells_by_city = {}
    for p in pack.get("places", []):
        if p.get("kind") != "city":
            continue
        pid = p.get("id", "")
        cset = set()
        for r in p.get("rows", []):
            if not r:
                continue
            cy = int(r[0])
            i = 1
            while i + 2 < len(r):
                cx0 = int(r[i])
                rlen = int(r[i + 1])
                for dx in range(rlen):
                    cset.add((cx0 + dx, cy))
                i += 3
        cells_by_city[pid] = cset
    return cells_by_city


def _block_bounds(anchor: dict, cells: list):
    ac_x, ac_y = grid.latlon_to_cell(float(anchor["lat"]), float(anchor["lon"]))
    cols, rows = int(cells[0]), int(cells[1])
    ox = ac_x - (cols - 1) // 2
    oy = ac_y - (rows - 1) // 2
    return ox, ox + cols - 1, oy, oy + rows - 1


def validate_neighbourhoods(
    config_path: str = "",
    famous_places_path: str = "",
    tuning_path: str = "",
    pack_path: str = "",
    caricature_dir: str = "",
):
    if not config_path:
        config_path = os.path.join(REPO_ROOT, "game", "config", "neighbourhoods.json")
    if not famous_places_path:
        famous_places_path = os.path.join(REPO_ROOT, "game", "config", "famous_places.json")
    if not tuning_path:
        tuning_path = os.path.join(REPO_ROOT, "game", "config", "tuning.json")
    if not pack_path:
        pack_path = os.path.join(REPO_ROOT, "game", "data", "places_pack_v1.json.gz")
    if not caricature_dir:
        caricature_dir = os.path.join(REPO_ROOT, "game", "data", "caricature")

    # N1: file parses; version is 1; every place_id is a kind=city entry of famous_places.json; no city appears twice
    if not os.path.isfile(config_path):
        raise RuleError("N1", f"file not found: {config_path}")
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            root = json.load(f)
    except Exception as exc:
        raise RuleError("N1", f"JSON parse error: {exc}") from exc

    if not isinstance(root, dict):
        raise RuleError("N1", "root must be a JSON object")
    if not _is_int(root.get("version")) or root.get("version") != 1:
        raise RuleError("N1", f"expected version 1, got {root.get('version')!r}")
    cities = root.get("cities")
    if not isinstance(cities, list):
        raise RuleError("N1", "'cities' must be a list")

    with open(famous_places_path, "r", encoding="utf-8") as f:
        famous_places = json.load(f)
    famous_cities = {
        p["id"]: p
        for p in famous_places
        if isinstance(p, dict) and p.get("kind") == "city" and isinstance(p.get("id"), str)
    }

    with open(tuning_path, "r", encoding="utf-8") as f:
        tuning = json.load(f)
    hoods_per_city = int(tuning["neighbourhoodsPerCity"])
    gateway_count = int(tuning["gatewayCount"])

    seen_cities = set()
    for c in cities:
        if not isinstance(c, dict):
            raise RuleError("N1", "city entry must be an object")
        pid = c.get("place_id")
        if not isinstance(pid, str) or pid not in famous_cities:
            raise RuleError("N1", f"place_id {pid!r} is not a kind='city' entry in famous_places.json")
        if pid in seen_cities:
            raise RuleError("N1", f"duplicate city entry for {pid}")
        seen_cities.add(pid)

    # N2: each city has one camp and exactly neighbourhoodsPerCity neighbourhoods
    for c in cities:
        pid = c["place_id"]
        camp = c.get("camp")
        if not isinstance(camp, dict) or not camp:
            raise RuleError("N2", f"{pid} missing camp object")
        hoods = c.get("neighbourhoods")
        if not isinstance(hoods, list) or len(hoods) != hoods_per_city:
            got = len(hoods) if isinstance(hoods, list) else type(hoods).__name__
            raise RuleError(
                "N2",
                f"{pid} has {got} neighbourhoods, expected {hoods_per_city}",
            )
        for h in hoods:
            if not isinstance(h, dict):
                raise RuleError("N2", f"{pid} neighbourhood entry must be an object")

    # N3: ids unique in file; hood:<slug>:<name> ([a-z0-9-]+) and camp:<slug>
    seen_ids = set()
    for c in cities:
        pid = c["place_id"]
        slug = pid[len("city:") :]
        camp_id = c["camp"].get("id")
        expected_camp_id = f"camp:{slug}"
        if not isinstance(camp_id, str) or camp_id != expected_camp_id:
            raise RuleError("N3", f"{pid} camp id {camp_id!r} != {expected_camp_id!r}")
        if camp_id in seen_ids:
            raise RuleError("N3", f"duplicate id {camp_id!r}")
        seen_ids.add(camp_id)

        hood_pat = re.compile(rf"^hood:{re.escape(slug)}:([a-z0-9-]+)$")
        for h in c["neighbourhoods"]:
            hid = h.get("id")
            if not isinstance(hid, str) or not hood_pat.match(hid):
                raise RuleError("N3", f"invalid neighbourhood id {hid!r} for {pid}")
            if hid in seen_ids:
                raise RuleError("N3", f"duplicate id {hid!r}")
            seen_ids.add(hid)

    # N4: role counts (gatewayCount gateway, 1 finale, rest inner)
    for c in cities:
        pid = c["place_id"]
        hoods = c["neighbourhoods"]
        for h in hoods:
            if h.get("role") not in VALID_ROLES:
                raise RuleError("N4", f"{h['id']} invalid role {h.get('role')!r}")
        gw = [h for h in hoods if h["role"] == "gateway"]
        fin = [h for h in hoods if h["role"] == "finale"]
        inn = [h for h in hoods if h["role"] == "inner"]
        if len(gw) != gateway_count or len(fin) != 1 or len(inn) != hoods_per_city - gateway_count - 1:
            raise RuleError(
                "N4",
                f"{pid} roles gateway={len(gw)}, finale={len(fin)}, inner={len(inn)} "
                f"(expected gateway={gateway_count}, finale=1, inner={hoods_per_city - gateway_count - 1})",
            )

    # N5: gateways are the gatewayCount non-finale neighbourhoods with smallest ground distance from waypost
    for c in cities:
        pid = c["place_id"]
        wp = famous_cities[pid]["waypost"]
        wp_lat, wp_lon = float(wp["lat"]), float(wp["lon"])

        camp_anchor = c["camp"].get("anchor")
        if not isinstance(camp_anchor, dict) or not _is_num(camp_anchor.get("lat")) or not _is_num(camp_anchor.get("lon")):
            raise RuleError("N5", f"{c['camp']['id']} missing valid anchor lat/lon")

        non_finale = []
        actual_gateways = set()
        for h in c["neighbourhoods"]:
            anc = h.get("anchor")
            if not isinstance(anc, dict) or not _is_num(anc.get("lat")) or not _is_num(anc.get("lon")):
                raise RuleError("N5", f"{h['id']} missing valid anchor lat/lon")
            if h["role"] == "gateway":
                actual_gateways.add(h["id"])
            if h["role"] != "finale":
                dist = grid.ground_distance_m(wp_lat, wp_lon, float(anc["lat"]), float(anc["lon"]))
                non_finale.append((dist, h["id"]))
        non_finale.sort(key=lambda item: (item[0], item[1]))
        expected_gateways = {hid for _, hid in non_finale[:gateway_count]}
        if actual_gateways != expected_gateways:
            raise RuleError(
                "N5",
                f"{pid} gateways {sorted(actual_gateways)} != nearest {gateway_count} non-finale {sorted(expected_gateways)}",
            )

    # N6: neighbourhood cells is [2, 2] or [3, 2]; camp cells is [1, 1]
    for c in cities:
        camp = c["camp"]
        cc = camp.get("cells")
        if not isinstance(cc, list) or len(cc) != 2 or not all(_is_int(v) for v in cc) or cc != [1, 1]:
            raise RuleError("N6", f"{camp['id']} cells must be [1, 1], got {cc!r}")
        for h in c["neighbourhoods"]:
            hc = h.get("cells")
            if (
                not isinstance(hc, list)
                or len(hc) != 2
                or not all(_is_int(v) for v in hc)
                or hc not in ([2, 2], [3, 2])
            ):
                raise RuleError("N6", f"{h['id']} cells must be [2, 2] or [3, 2], got {hc!r}")

    # N7: every cell of every block belongs to that city in places_pack_v1.json.gz
    pack_cells_by_city = _load_pack_cells_by_city(pack_path)
    all_blocks = []  # (area_id, x0, x1, y0, y1) across whole file for N8
    for c in cities:
        pid = c["place_id"]
        city_cells = pack_cells_by_city.get(pid, set())
        areas = [c["camp"]] + list(c["neighbourhoods"])
        for area in areas:
            aid = area["id"]
            x0, x1, y0, y1 = _block_bounds(area["anchor"], area["cells"])
            for cx in range(x0, x1 + 1):
                for cy in range(y0, y1 + 1):
                    if (cx, cy) not in city_cells:
                        raise RuleError("N7", f"{aid} cell ({cx}, {cy}) is outside {pid} in places pack")
            all_blocks.append((aid, x0, x1, y0, y1))

    # N8: any two blocks in the file are at least 2 cells apart (larger of column and row gaps)
    for i in range(len(all_blocks)):
        aid1, x1a, x1b, y1a, y1b = all_blocks[i]
        for j in range(i + 1, len(all_blocks)):
            aid2, x2a, x2b, y2a, y2b = all_blocks[j]
            col_gap = max(0, x2a - x1b, x1a - x2b)
            row_gap = max(0, y2a - y1b, y1a - y2b)
            if max(col_gap, row_gap) < 2:
                raise RuleError(
                    "N8",
                    f"blocks {aid1} and {aid2} gap is {max(col_gap, row_gap)} (col={col_gap}, row={row_gap}), expected >= 2",
                )

    # N9: borders same city, never self, symmetric, every inner reachable from gateway without passing through finale
    for c in cities:
        pid = c["place_id"]
        hoods_by_id = {h["id"]: h for h in c["neighbourhoods"]}
        for hid, h in hoods_by_id.items():
            borders = h.get("borders")
            if not isinstance(borders, list):
                raise RuleError("N9", f"{hid} borders must be a list")
            if len(borders) != len(set(borders)):
                raise RuleError("N9", f"{hid} has duplicate entries in borders")
            for b in borders:
                if not isinstance(b, str) or b not in hoods_by_id:
                    raise RuleError("N9", f"{hid} border {b!r} is not a neighbourhood of {pid}")
                if b == hid:
                    raise RuleError("N9", f"{hid} borders itself")
        for hid, h in hoods_by_id.items():
            for b in h["borders"]:
                if hid not in hoods_by_id[b]["borders"]:
                    raise RuleError("N9", f"border {hid} -> {b} is not symmetric")

        visited = {hid for hid, h in hoods_by_id.items() if h["role"] == "gateway"}
        queue = collections.deque(visited)
        while queue:
            cur = queue.popleft()
            for nxt in hoods_by_id[cur]["borders"]:
                if hoods_by_id[nxt]["role"] == "finale":
                    continue
                if nxt not in visited:
                    visited.add(nxt)
                    queue.append(nxt)
        for hid, h in hoods_by_id.items():
            if h["role"] == "inner" and hid not in visited:
                raise RuleError("N9", f"inner neighbourhood {hid} cannot be reached from any gateway without finale")

    # N10: zone, haunt_site, ruin_level (and camp's ruin_level is camp)
    for c in cities:
        camp = c["camp"]
        if not _is_nonempty_str(camp.get("name")):
            raise RuleError("N10", f"{camp['id']} missing name")
        if camp.get("ruin_level") != "camp":
            raise RuleError("N10", f"{camp['id']} ruin_level must be 'camp', got {camp.get('ruin_level')!r}")
        for h in c["neighbourhoods"]:
            hid = h["id"]
            if not _is_nonempty_str(h.get("name")):
                raise RuleError("N10", f"{hid} missing name")
            if h.get("zone") not in VALID_ZONES:
                raise RuleError("N10", f"{hid} invalid zone {h.get('zone')!r}")
            if h.get("haunt_site") not in VALID_HAUNT_SITES:
                raise RuleError("N10", f"{hid} invalid haunt_site {h.get('haunt_site')!r}")
            if h.get("ruin_level") not in VALID_RUIN_LEVELS:
                raise RuleError("N10", f"{hid} invalid ruin_level {h.get('ruin_level')!r}")

    # N11: >= 2 landmarks per neighbourhood, >= 1 with stamp; each has name and xor(stamp, feature); feature has non-empty sign
    for c in cities:
        for h in c["neighbourhoods"]:
            hid = h["id"]
            lms = h.get("landmarks")
            if not isinstance(lms, list) or len(lms) < 2:
                raise RuleError("N11", f"{hid} must have at least 2 landmarks")
            stamp_count = 0
            for lm in lms:
                if not isinstance(lm, dict):
                    raise RuleError("N11", f"{hid} landmark must be an object")
                if not _is_nonempty_str(lm.get("name")):
                    raise RuleError("N11", f"{hid} landmark missing non-empty name")
                has_stamp = "stamp" in lm
                has_feature = "feature" in lm
                if has_stamp == has_feature:
                    raise RuleError("N11", f"{hid} landmark {lm.get('name')!r} must have exactly one of 'stamp' or 'feature'")
                if has_stamp:
                    if not _is_nonempty_str(lm.get("stamp")):
                        raise RuleError("N11", f"{hid} landmark {lm.get('name')!r} has empty stamp")
                    stamp_count += 1
                else:
                    if not _is_nonempty_str(lm.get("feature")):
                        raise RuleError("N11", f"{hid} landmark {lm.get('name')!r} has empty feature")
                    if not _is_nonempty_str(lm.get("sign")):
                        raise RuleError("N11", f"{hid} feature landmark {lm.get('name')!r} missing non-empty sign")
            if stamp_count < 1:
                raise RuleError("N11", f"{hid} must have at least one stamp landmark")

    # N12: every interior id of city in famous_places.json appears on exactly one landmark of that city, and no foreign interior
    for c in cities:
        pid = c["place_id"]
        expected_interiors = {
            item["id"] for item in famous_cities[pid].get("interiors", []) if isinstance(item, dict) and "id" in item
        }
        seen_interiors = []
        for h in c["neighbourhoods"]:
            for lm in h["landmarks"]:
                if "interior" in lm:
                    iid = lm.get("interior")
                    if not _is_nonempty_str(iid) or iid not in expected_interiors:
                        raise RuleError("N12", f"{h['id']} landmark names unknown/foreign interior {iid!r} for {pid}")
                    if iid in seen_interiors:
                        raise RuleError("N12", f"{pid} interior {iid!r} appears more than once")
                    seen_interiors.append(iid)
        missing_interiors = expected_interiors - set(seen_interiors)
        if missing_interiors:
            raise RuleError("N12", f"{pid} missing interiors from famous_places.json: {sorted(missing_interiors)}")

    # N13: main_quest has non-empty title, pattern, pays, summary; source in roster/lair/new; new quest pattern in 7
    for c in cities:
        for h in c["neighbourhoods"]:
            hid = h["id"]
            mq = h.get("main_quest")
            if not isinstance(mq, dict):
                raise RuleError("N13", f"{hid} missing main_quest object")
            for field in ("title", "pattern", "pays", "summary"):
                if not _is_nonempty_str(mq.get(field)):
                    raise RuleError("N13", f"{hid} main_quest missing non-empty {field!r}")
            src = mq.get("source")
            if src not in VALID_SOURCES:
                raise RuleError("N13", f"{hid} main_quest invalid source {src!r}")
            if src == "new" and mq["pattern"] not in VALID_NEW_PATTERNS:
                raise RuleError("N13", f"{hid} new main_quest has invalid pattern {mq['pattern']!r}")

    # N14: ready is true or false; when true, every area's map file exists under game/data/caricature/
    for c in cities:
        pid = c["place_id"]
        ready = c.get("ready")
        if type(ready) is not bool:
            raise RuleError("N14", f"{pid} 'ready' must be boolean true or false, got {ready!r}")
        areas = [c["camp"]] + list(c["neighbourhoods"])
        for area in areas:
            mpath = area.get("map")
            if not _is_nonempty_str(mpath):
                raise RuleError("N14", f"{area['id']} missing non-empty map path")
            if ready:
                full_path = os.path.join(caricature_dir, mpath)
                if not os.path.isfile(full_path):
                    raise RuleError("N14", f"{area['id']} map file missing at {full_path}")

    n_cities = len(cities)
    n_hoods = sum(len(c["neighbourhoods"]) for c in cities)
    n_camps = len(cities)
    return n_cities, n_hoods, n_camps


def check_neighbourhoods_cli(config_path: str = ""):
    try:
        n_cities, n_hoods, n_camps = validate_neighbourhoods(config_path=config_path)
        return 0, f"[CHECK NEIGHBOURHOODS OK] {n_cities} cities, {n_hoods} neighbourhoods, {n_camps} camps."
    except RuleError as exc:
        return 1, f"[CHECK NEIGHBOURHOODS FAIL] {exc.rule_id}: {exc.message}"
    except Exception as exc:
        return 1, f"[CHECK NEIGHBOURHOODS FAIL] N1: {exc}"


def main():
    cfg = sys.argv[1] if len(sys.argv) > 1 else ""
    code, msg = check_neighbourhoods_cli(cfg)
    print(msg)
    sys.exit(code)


if __name__ == "__main__":
    main()
