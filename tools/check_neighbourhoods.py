#!/usr/bin/env python3
"""
tools/check_neighbourhoods.py — Validate game/config/neighbourhoods.json (Items 47, 53)
Contract: docs/implementation_plan_dc_trial.md §1.4 & §10.3, docs/design_neighbourhoods_and_caricature.md §2–§7
"""

import collections
import gzip
import json
import math
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


def _shared_edge_cells(rect_a: tuple, rect_b: tuple):
    ax0, ax1, ay0, ay1 = rect_a
    bx0, bx1, by0, by1 = rect_b
    if ax1 + 1 == bx0:
        y0, y1 = max(ay0, by0), min(ay1, by1)
        if y0 <= y1:
            return (1, 0), [(ax1, y) for y in range(y0, y1 + 1)], [(bx0, y) for y in range(y0, y1 + 1)]
    if bx1 + 1 == ax0:
        y0, y1 = max(ay0, by0), min(ay1, by1)
        if y0 <= y1:
            return (-1, 0), [(ax0, y) for y in range(y0, y1 + 1)], [(bx1, y) for y in range(y0, y1 + 1)]
    if ay1 + 1 == by0:
        x0, x1 = max(ax0, bx0), min(ax1, bx1)
        if x0 <= x1:
            return (0, 1), [(x, ay1) for x in range(x0, x1 + 1)], [(x, by0) for x in range(x0, x1 + 1)]
    if by1 + 1 == ay0:
        x0, x1 = max(ax0, bx0), min(ax1, bx1)
        if x0 <= x1:
            return (0, -1), [(x, ay0) for x in range(x0, x1 + 1)], [(x, by1) for x in range(x0, x1 + 1)]
    return None


def _validate_landmark_obj(owner_id: str, lm: dict) -> bool:
    """Validate one landmark entry under N11. Returns True if it carries a 'stamp'."""
    if not isinstance(lm, dict):
        raise RuleError("N11", f"{owner_id} landmark must be an object")
    if not _is_nonempty_str(lm.get("name")):
        raise RuleError("N11", f"{owner_id} landmark missing non-empty name")
    has_stamp = "stamp" in lm
    has_feature = "feature" in lm
    if has_stamp == has_feature:
        raise RuleError(
            "N11",
            f"{owner_id} landmark {lm.get('name')!r} must have exactly one of 'stamp' or 'feature'",
        )
    if has_stamp:
        if not _is_nonempty_str(lm.get("stamp")):
            raise RuleError("N11", f"{owner_id} landmark {lm.get('name')!r} has empty stamp")
        return True
    if not _is_nonempty_str(lm.get("feature")):
        raise RuleError("N11", f"{owner_id} landmark {lm.get('name')!r} has empty feature")
    if not _is_nonempty_str(lm.get("sign")):
        raise RuleError("N11", f"{owner_id} feature landmark {lm.get('name')!r} missing non-empty sign")
    return False


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
        if "routes" in c and not isinstance(c.get("routes"), list):
            raise RuleError("N1", f"{pid} 'routes' must be a list")

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

    # N3: ids unique in file; hood:<slug>:<name>, camp:<slug>, and route:<slug>:<name>
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

        if "routes" in c:
            route_pat = re.compile(rf"^route:{re.escape(slug)}:([a-z0-9-]+)$")
            for r in c["routes"]:
                if not isinstance(r, dict):
                    raise RuleError("N3", f"{pid} route entry must be an object")
                rid = r.get("id")
                if not isinstance(rid, str) or not route_pat.match(rid):
                    raise RuleError("N3", f"invalid route id {rid!r} for {pid}")
                if rid in seen_ids:
                    raise RuleError("N3", f"duplicate id {rid!r}")
                seen_ids.add(rid)

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

    # N6: for cities with routes (Decision 58), camp is [2, 2] and neighbourhoods [4, 3], [4, 4], or [5, 4];
    #     for cities without routes (Item 53 transition), camp is [1, 1] and neighbourhoods [2, 2] or [3, 2].
    for c in cities:
        camp = c["camp"]
        cc = camp.get("cells")
        has_routes = "routes" in c
        expected_camp_cells = [2, 2] if has_routes else [1, 1]
        valid_hood_cells = ([4, 3], [4, 4], [5, 4]) if has_routes else ([2, 2], [3, 2])
        if not isinstance(cc, list) or len(cc) != 2 or not all(_is_int(v) for v in cc) or cc != expected_camp_cells:
            raise RuleError("N6", f"{camp['id']} cells must be {expected_camp_cells}, got {cc!r}")
        for h in c["neighbourhoods"]:
            hc = h.get("cells")
            if (
                not isinstance(hc, list)
                or len(hc) != 2
                or not all(_is_int(v) for v in hc)
                or hc not in valid_hood_cells
            ):
                raise RuleError("N6", f"{h['id']} cells must be in {valid_hood_cells}, got {hc!r}")

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

    # Layout rules: L1–L8 for cities with routes (§10.3); legacy N7 & N8 for cities without routes during Item 53.
    pack_cells_by_city = _load_pack_cells_by_city(pack_path)
    legacy_blocks = []  # (area_id, x0, x1, y0, y1) across legacy cities for N8
    all_route_blocks = []  # (block_id, x0, x1, y0, y1) across route cities
    all_allowed_touch = set()

    for c in cities:
        pid = c["place_id"]
        city_cells = pack_cells_by_city.get(pid, set())
        if "routes" not in c:
            areas = [c["camp"]] + list(c["neighbourhoods"])
            for area in areas:
                aid = area["id"]
                x0, x1, y0, y1 = _block_bounds(area["anchor"], area["cells"])
                for cx in range(x0, x1 + 1):
                    for cy in range(y0, y1 + 1):
                        if (cx, cy) not in city_cells:
                            raise RuleError("N7", f"{aid} cell ({cx}, {cy}) is outside {pid} in places pack")
                legacy_blocks.append((aid, x0, x1, y0, y1))
            continue

        # City with routes: L1–L8
        camp = c["camp"]
        if "at" in camp:
            raise RuleError("L1", f"{camp['id']} must not have 'at'")
        for h in c["neighbourhoods"]:
            hat = h.get("at")
            if not (isinstance(hat, list) and len(hat) == 2 and all(_is_int(v) for v in hat)):
                raise RuleError("L1", f"{h['id']} missing valid 'at' [dx, dy]")

        for r in c["routes"]:
            rid = r["id"]
            ends = r.get("ends")
            if isinstance(ends, list) and camp["id"] in ends:
                raise RuleError("L3", f"{rid} ends may not include camp {camp['id']}")
            legs = r.get("legs")
            if not isinstance(legs, list) or not (1 <= len(legs) <= 2):
                raise RuleError("L3", f"{rid} must have 1 or 2 legs")
            for idx, leg in enumerate(legs, 1):
                if not isinstance(leg, dict):
                    raise RuleError("L3", f"{rid}#{idx} must be an object")
                lat_off = leg.get("at")
                if not (isinstance(lat_off, list) and len(lat_off) == 2 and all(_is_int(v) for v in lat_off)):
                    raise RuleError("L1", f"{rid}#{idx} missing valid 'at' [dx, dy]")
                lc = leg.get("cells")
                if (
                    not (isinstance(lc, list) and len(lc) == 2 and all(_is_int(v) for v in lc))
                    or lc[0] < 1
                    or lc[1] < 1
                    or (lc[0] != 1 and lc[1] != 1)
                ):
                    raise RuleError("L3", f"{rid}#{idx} cells must be [n, 1] or [1, n] with n >= 1, got {lc!r}")

        camp_ox, camp_x1, camp_oy, camp_y1 = _block_bounds(camp["anchor"], camp["cells"])
        city_blocks = [(camp["id"], camp_ox, camp_x1, camp_oy, camp_y1)]
        bounds_by_id = {camp["id"]: (camp_ox, camp_x1, camp_oy, camp_y1)}

        for h in c["neighbourhoods"]:
            ox = camp_ox + h["at"][0]
            oy = camp_oy + h["at"][1]
            cols, rows = h["cells"]
            b = (ox, ox + cols - 1, oy, oy + rows - 1)
            city_blocks.append((h["id"], *b))
            bounds_by_id[h["id"]] = b

        for r in c["routes"]:
            rid = r["id"]
            legs = r["legs"]
            for idx, leg in enumerate(legs, 1):
                lid = f"{rid}#{idx}"
                ox = camp_ox + leg["at"][0]
                oy = camp_oy + leg["at"][1]
                cols, rows = leg["cells"]
                b = (ox, ox + cols - 1, oy, oy + rows - 1)
                city_blocks.append((lid, *b))
                bounds_by_id[lid] = b
            ends = r.get("ends")
            if isinstance(ends, list) and len(ends) == 2 and all(isinstance(e, str) for e in ends):
                l1_id = f"{rid}#1"
                all_allowed_touch.add(frozenset({ends[0], l1_id}))
                if len(legs) == 1:
                    all_allowed_touch.add(frozenset({l1_id, ends[1]}))
                else:
                    l2_id = f"{rid}#2"
                    all_allowed_touch.add(frozenset({l1_id, l2_id}))
                    all_allowed_touch.add(frozenset({l2_id, ends[1]}))

        # L1: no two blocks overlap
        for i in range(len(city_blocks)):
            id1, x1a, x1b, y1a, y1b = city_blocks[i]
            for j in range(i + 1, len(city_blocks)):
                id2, x2a, x2b, y2a, y2b = city_blocks[j]
                if x1a <= x2b and x2a <= x1b and y1a <= y2b and y2a <= y1b:
                    raise RuleError("L1", f"blocks {id1} and {id2} overlap")

        # L2: Chebyshev cell distance 1 allowed only between consecutive blocks in a route's chain
        for i in range(len(city_blocks)):
            id1, x1a, x1b, y1a, y1b = city_blocks[i]
            for j in range(i + 1, len(city_blocks)):
                id2, x2a, x2b, y2a, y2b = city_blocks[j]
                col_gap = max(0, x2a - x1b, x1a - x2b)
                row_gap = max(0, y2a - y1b, y1a - y2b)
                cheb = max(col_gap, row_gap)
                if cheb < 2 and frozenset({id1, id2}) not in all_allowed_touch:
                    raise RuleError(
                        "L2",
                        f"blocks {id1} and {id2} have Chebyshev cell distance {cheb} without following each other in a route chain",
                    )

        # L7: every border pair has exactly one route, and every route's ends are a border pair of the same city
        hoods_by_id = {h["id"]: h for h in c["neighbourhoods"]}
        expected_pairs = {frozenset({hid, b}) for hid, h in hoods_by_id.items() for b in h["borders"]}
        seen_pairs = set()
        for r in c["routes"]:
            rid = r["id"]
            ends = r.get("ends")
            if not (isinstance(ends, list) and len(ends) == 2 and all(isinstance(e, str) for e in ends)):
                raise RuleError("L7", f"{rid} 'ends' must be a 2-element list of neighbourhood ids")
            e0, e1 = ends[0], ends[1]
            if e0 == e1 or e0 not in hoods_by_id or e1 not in hoods_by_id or e1 not in hoods_by_id[e0]["borders"]:
                raise RuleError("L7", f"{rid} ends {ends!r} are not a border pair of {pid}")
            pair = frozenset({e0, e1})
            if pair in seen_pairs:
                raise RuleError("L7", f"duplicate route {rid} for border pair {sorted(pair)}")
            seen_pairs.add(pair)
        if seen_pairs != expected_pairs:
            missing = [sorted(p) for p in sorted(expected_pairs - seen_pairs, key=lambda s: sorted(s))]
            raise RuleError("L7", f"{pid} missing route(s) for border pair(s): {missing}")

        # L4, L5, L6 per route
        for r in c["routes"]:
            rid = r["id"]
            e0, e1 = r["ends"][0], r["ends"][1]
            legs = r["legs"]
            l1_id = f"{rid}#1"
            edge0 = _shared_edge_cells(bounds_by_id[e0], bounds_by_id[l1_id])
            if edge0 is None:
                raise RuleError("L4", f"{rid} leg 1 does not share an edge with {e0}")
            dir1, _, l1_entry = edge0
            c1, r1 = legs[0]["cells"]
            if (c1 > 1 and dir1[0] == 0) or (r1 > 1 and dir1[1] == 0) or len(l1_entry) != 1:
                raise RuleError("L4", f"{rid} leg 1 does not meet {e0} at one of its short ends")
            first1 = l1_entry[0]
            n1 = max(c1, r1)
            last1 = (first1[0] + dir1[0] * (n1 - 1), first1[1] + dir1[1] * (n1 - 1))

            if len(legs) == 1:
                edge1 = _shared_edge_cells(bounds_by_id[l1_id], bounds_by_id[e1])
                if edge1 is None:
                    raise RuleError("L4", f"{rid} leg 1 does not share an edge with {e1}")
                dir_out, l1_exit, _ = edge1
                if dir_out != dir1 or l1_exit != [last1]:
                    raise RuleError("L4", f"{rid} leg 1 does not meet {e1} at its other short end")
                dirs = [dir1]
            else:
                l2_id = f"{rid}#2"
                edge12 = _shared_edge_cells(bounds_by_id[l1_id], bounds_by_id[l2_id])
                if edge12 is None:
                    raise RuleError("L4", f"{rid} leg 1 and leg 2 do not share an edge")
                dir2, l1_touch, l2_entry = edge12
                c2, r2 = legs[1]["cells"]
                if dir1[0] * dir2[0] + dir1[1] * dir2[1] != 0:
                    raise RuleError("L4", f"{rid} leg 2 does not meet leg 1 on its long side at a right angle")
                if (c2 > 1 and dir2[0] == 0) or (r2 > 1 and dir2[1] == 0) or len(l2_entry) != 1 or l1_touch != [last1]:
                    raise RuleError("L4", f"{rid} leg 2 does not meet leg 1's last cell {last1} at leg 2's short end")
                first2 = l2_entry[0]
                n2 = max(c2, r2)
                last2 = (first2[0] + dir2[0] * (n2 - 1), first2[1] + dir2[1] * (n2 - 1))
                edge2 = _shared_edge_cells(bounds_by_id[l2_id], bounds_by_id[e1])
                if edge2 is None:
                    raise RuleError("L4", f"{rid} leg 2 does not share an edge with {e1}")
                dir_out, l2_exit, _ = edge2
                if dir_out != dir2 or l2_exit != [last2]:
                    raise RuleError("L4", f"{rid} leg 2 does not meet {e1} at its other short end")
                dirs = [dir1, dir2]

            # L5: Compass
            a0, a1 = hoods_by_id[e0]["anchor"], hoods_by_id[e1]["anchor"]
            lat0, lon0 = float(a0["lat"]), float(a0["lon"])
            lat1, lon1 = float(a1["lat"]), float(a1["lon"])
            mid_lat = 0.5 * (lat0 + lat1)
            east_km = (
                (1.0 if lon1 >= lon0 else -1.0) * (grid.ground_distance_m(mid_lat, lon0, mid_lat, lon1) / 1000.0)
                if lon1 != lon0
                else 0.0
            )
            north_km = (
                (1.0 if lat1 >= lat0 else -1.0) * (grid.ground_distance_m(lat0, lon0, lat1, lon0) / 1000.0)
                if lat1 != lat0
                else 0.0
            )
            major = max(abs(east_km), abs(north_km))
            for dx, dy in dirs:
                if dx != 0:
                    if (dx > 0 and east_km <= 0.0) or (dx < 0 and east_km >= 0.0) or abs(east_km) < 0.5 * major:
                        raise RuleError(
                            "L5",
                            f"{rid} travels {'E' if dx > 0 else 'W'} but real displacement is east={east_km:.2f} km, north={north_km:.2f} km",
                        )
                if dy != 0:
                    if (dy > 0 and north_km <= 0.0) or (dy < 0 and north_km >= 0.0) or abs(north_km) < 0.5 * major:
                        raise RuleError(
                            "L5",
                            f"{rid} travels {'N' if dy > 0 else 'S'} but real displacement is east={east_km:.2f} km, north={north_km:.2f} km",
                        )

            # L6: Length (1.25 to 3.75 cells per real km, clamped to 2..8)
            km = grid.ground_distance_m(lat0, lon0, lat1, lon1) / 1000.0
            lo = max(2, math.ceil(1.25 * km))
            hi = min(8, max(lo, math.floor(3.75 * km)))
            total_cells = sum(max(int(leg["cells"][0]), int(leg["cells"][1])) for leg in legs)
            if not (lo <= total_cells <= hi):
                raise RuleError("L6", f"{rid} has {total_cells} leg cells, expected {lo}..{hi} for {km:.2f} km")

        # L8: every cell of every block — legs included — belongs to the city in the places pack
        for bid, x0, x1, y0, y1 in city_blocks:
            for cx in range(x0, x1 + 1):
                for cy in range(y0, y1 + 1):
                    if (cx, cy) not in city_cells:
                        raise RuleError("L8", f"{bid} cell ({cx}, {cy}) is outside {pid} in places pack")

        all_route_blocks.extend(city_blocks)

    # Cross-city block spacing: legacy N8 among legacy cities; L1/L2 across route cities
    for i in range(len(legacy_blocks)):
        aid1, x1a, x1b, y1a, y1b = legacy_blocks[i]
        for j in range(i + 1, len(legacy_blocks)):
            aid2, x2a, x2b, y2a, y2b = legacy_blocks[j]
            col_gap = max(0, x2a - x1b, x1a - x2b)
            row_gap = max(0, y2a - y1b, y1a - y2b)
            if max(col_gap, row_gap) < 2:
                raise RuleError(
                    "N8",
                    f"blocks {aid1} and {aid2} gap is {max(col_gap, row_gap)} (col={col_gap}, row={row_gap}), expected >= 2",
                )

    combined_blocks = all_route_blocks + legacy_blocks
    if all_route_blocks:
        for i in range(len(all_route_blocks)):
            id1, x1a, x1b, y1a, y1b = all_route_blocks[i]
            for j in range(i + 1, len(combined_blocks)):
                id2, x2a, x2b, y2a, y2b = combined_blocks[j]
                if x1a <= x2b and x2a <= x1b and y1a <= y2b and y2a <= y1b:
                    raise RuleError("L1", f"blocks {id1} and {id2} overlap")
                col_gap = max(0, x2a - x1b, x1a - x2b)
                row_gap = max(0, y2a - y1b, y1a - y2b)
                cheb = max(col_gap, row_gap)
                if cheb < 2 and frozenset({id1, id2}) not in all_allowed_touch:
                    raise RuleError("L2", f"blocks {id1} and {id2} touch across cities (Chebyshev distance {cheb})")

    # N10: zone, haunt_site, ruin_level (and routes' name, zone, ruin_level, calm)
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
        for r in c.get("routes", []):
            rid = r["id"]
            if not _is_nonempty_str(r.get("name")):
                raise RuleError("N10", f"{rid} missing name")
            if r.get("zone") not in VALID_ZONES:
                raise RuleError("N10", f"{rid} invalid zone {r.get('zone')!r}")
            if r.get("ruin_level") not in VALID_RUIN_LEVELS:
                raise RuleError("N10", f"{rid} invalid ruin_level {r.get('ruin_level')!r}")
            if type(r.get("calm")) is not bool:
                raise RuleError("N10", f"{rid} 'calm' must be boolean, got {r.get('calm')!r}")

    # N11: >= 2 landmarks per neighbourhood (>= 1 stamp); >= 1 landmark per route; valid schema
    for c in cities:
        for h in c["neighbourhoods"]:
            hid = h["id"]
            lms = h.get("landmarks")
            if not isinstance(lms, list) or len(lms) < 2:
                raise RuleError("N11", f"{hid} must have at least 2 landmarks")
            stamp_count = sum(1 for lm in lms if _validate_landmark_obj(hid, lm))
            if stamp_count < 1:
                raise RuleError("N11", f"{hid} must have at least one stamp landmark")
        for r in c.get("routes", []):
            rid = r["id"]
            lms = r.get("landmarks")
            if not isinstance(lms, list) or len(lms) < 1:
                raise RuleError("N11", f"{rid} must have at least 1 landmark")
            for lm in lms:
                _validate_landmark_obj(rid, lm)

    # N12: every interior id of city in famous_places.json appears on exactly one landmark of that city, and no foreign interior
    for c in cities:
        pid = c["place_id"]
        expected_interiors = {
            item["id"] for item in famous_cities[pid].get("interiors", []) if isinstance(item, dict) and "id" in item
        }
        seen_interiors = []
        for owner in list(c["neighbourhoods"]) + list(c.get("routes", [])):
            for lm in owner["landmarks"]:
                if "interior" in lm:
                    iid = lm.get("interior")
                    if not _is_nonempty_str(iid) or iid not in expected_interiors:
                        raise RuleError("N12", f"{owner['id']} landmark names unknown/foreign interior {iid!r} for {pid}")
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

    # N14: ready is true or false; when true, every area's and leg's map file exists under game/data/caricature/
    for c in cities:
        pid = c["place_id"]
        ready = c.get("ready")
        if type(ready) is not bool:
            raise RuleError("N14", f"{pid} 'ready' must be boolean true or false, got {ready!r}")
        areas = [(a["id"], a.get("map")) for a in [c["camp"]] + list(c["neighbourhoods"])]
        for r in c.get("routes", []):
            for idx, leg in enumerate(r["legs"], 1):
                areas.append((f"{r['id']}#{idx}", leg.get("map")))
        for aid, mpath in areas:
            if not _is_nonempty_str(mpath):
                raise RuleError("N14", f"{aid} missing non-empty map path")
            if ready:
                full_path = os.path.join(caricature_dir, mpath)
                if not os.path.isfile(full_path):
                    raise RuleError("N14", f"{aid} map file missing at {full_path}")

    n_cities = len(cities)
    n_hoods = sum(len(c["neighbourhoods"]) for c in cities)
    n_camps = len(cities)
    n_routes = sum(len(c.get("routes", [])) for c in cities)
    n_legs = sum(len(r["legs"]) for c in cities for r in c.get("routes", []))
    return n_cities, n_hoods, n_camps, n_routes, n_legs


def check_neighbourhoods_cli(config_path: str = ""):
    try:
        n_cities, n_hoods, n_camps, n_routes, n_legs = validate_neighbourhoods(config_path=config_path)
        return (
            0,
            f"[CHECK NEIGHBOURHOODS OK] {n_cities} cities, {n_hoods} neighbourhoods, {n_camps} camps, {n_routes} routes, {n_legs} legs.",
        )
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
