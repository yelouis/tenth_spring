#!/usr/bin/env python3
"""
tools/build_places_pack.py — Build the Tenth Spring Places Pack (Item 26, F55, F67)
Contract:
  - docs/implementation_plan_explore_here.md §1
  - docs/implementation_plan_famous_places.md §8.2
  - docs/agent_execution_guide.md §6
"""

import argparse
import bisect
import gzip
import hashlib
import io
import json
import math
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Set, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grid  # noqa: E402

OVERPASS_ENDPOINT = "https://overpass-api.de/api/interpreter"
PINNED_DATE = "2026-10-01T00:00:00Z"
SNAPSHOT_ID = "261001"
PACK_VERSION = 1
ATTRIBUTION = "© OpenStreetMap contributors (ODbL)"
USER_AGENT = "TenthSpring-dev/1.0"
MIN_REQUEST_INTERVAL_S = 5.0
RETRY_WAIT_S = 60.0
MAX_RETRIES = 3
MAX_GZIP_BYTES = 4 * 1024 * 1024  # 4 MiB

# Known OSM boundary names that legitimately differ from display names in famous_places.json
KNOWN_BOUNDARY_NAME_ALIASES: Dict[str, Set[str]] = {
    "city:washington-dc": {"District of Columbia", "Washington, D.C.", "Washington DC"},
    "city:st-louis": {"Saint Louis", "St. Louis"},
    "site:hawaii-volcanoes": {"Hawaiʻi Volcanoes National Park", "Hawaii Volcanoes National Park"},
    "site:red-river-gorge": {"Clifty Wilderness", "Red River Gorge"},
    "site:barataria-preserve": {
        "Jean Lafitte National Historic Park and Preserve - Barataria Preserve Unit",
        "Barataria Preserve",
    },
    "site:pictured-rocks": {
        "Pictured Rocks National Lakeshore (Federal Unit)",
        "Pictured Rocks National Lakeshore",
    },
    "site:bonneville-salt-flats": {
        "Bonneville Speedway",
        "Bonneville Salt Flats",
        "Bonneville State Park",
    },
    "site:meteor-crater": {"Barringer Crater", "Meteor Crater"},
}


def parse_boundary_spec(spec: Any) -> Tuple[str, int]:
    """Return ('r' or 'w', numeric_id) from osm_boundary in famous_places.json."""
    if isinstance(spec, dict):
        if "relation_id" in spec:
            return ("r", int(spec["relation_id"]))
        if "way_id" in spec:
            return ("w", int(spec["way_id"]))
    s = str(spec).strip()
    m = re.match(r"^([rw])(\d+)$", s)
    if m:
        return (m.group(1), int(m.group(2)))
    if s.isdigit():
        return ("r", int(s))
    raise ValueError(f"Invalid osm_boundary spec: {spec!r}")


def strip_state_suffix(place_name: str) -> str:
    """Strip trailing ' (XX)' state/disambiguation suffix from famous_places.json name."""
    return re.sub(r"\s*\([^)]+\)\s*$", "", place_name).strip()


def validate_boundary_element(place: Dict[str, Any], data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate that the Overpass response contains the expected boundary element at the pinned date,
    that it is a boundary, protected area, park, or natural/historic site (never a road/bus route),
    and that its name matches the place (or is a documented alias).
    """
    pid = place["id"]
    pkind = place["kind"]
    pname = place["name"]
    b_type, b_id = parse_boundary_spec(place["osm_boundary"])
    expected_osm_type = "relation" if b_type == "r" else "way"

    elements = data.get("elements", [])
    target = None
    for el in elements:
        if el.get("type") == expected_osm_type and int(el.get("id", -1)) == b_id:
            target = el
            break

    if target is None:
        raise ValueError(
            f"Boundary {b_type}{b_id} for {pid} ({pname}) does not exist in Overpass response at {PINNED_DATE}"
        )

    tags = target.get("tags", {})
    if not tags:
        raise ValueError(f"Boundary {b_type}{b_id} for {pid} ({pname}) has no tags")

    # Reject route relations (e.g. old site:acadia r1257404)
    if tags.get("type") == "route" or "route" in tags:
        raise ValueError(
            f"Boundary {b_type}{b_id} for {pid} ({pname}) is a route ({tags.get('route')}), not a boundary or park"
        )

    if pkind == "city":
        if tags.get("boundary") != "administrative":
            raise ValueError(
                f"City {pid} boundary {b_type}{b_id} is not boundary=administrative: {tags}"
            )
    else:
        valid_site_tag = any(
            k in tags
            for k in ("boundary", "leisure", "tourism", "landuse", "natural", "historic")
        ) or tags.get("surface") == "salt"
        if not valid_site_tag:
            raise ValueError(
                f"Site {pid} boundary {b_type}{b_id} lacks boundary/park/site tags: {tags}"
            )

    osm_name = str(tags.get("name", "")).strip()
    if not osm_name:
        raise ValueError(f"Boundary {b_type}{b_id} for {pid} ({pname}) has no name tag")

    base_pname = strip_state_suffix(pname)
    allowed_names = {pname, base_pname} | KNOWN_BOUNDARY_NAME_ALIASES.get(pid, set())
    if (
        osm_name not in allowed_names
        and base_pname.lower() not in osm_name.lower()
        and osm_name.lower() not in base_pname.lower()
    ):
        raise ValueError(
            f"Boundary {b_type}{b_id} for {pid} has name {osm_name!r}, which does not match {pname!r}"
        )

    return target


class OverpassClient:
    def __init__(self, cache_dir: str, offline: bool = False):
        self.cache_dir = os.path.expanduser(cache_dir)
        self.offline = offline
        self._last_request_ts = 0.0
        os.makedirs(self.cache_dir, exist_ok=True)

    def _query_overpass(self, query: str) -> Dict[str, Any]:
        if self.offline:
            raise RuntimeError(f"Offline mode enabled, but cache miss for query:\n{query}")

        for attempt in range(MAX_RETRIES + 1):
            elapsed = time.monotonic() - self._last_request_ts
            if self._last_request_ts > 0.0 and elapsed < MIN_REQUEST_INTERVAL_S:
                time.sleep(MIN_REQUEST_INTERVAL_S - elapsed)

            req = urllib.request.Request(
                OVERPASS_ENDPOINT,
                data=urllib.parse.urlencode({"data": query}).encode("utf-8"),
                headers={"User-Agent": USER_AGENT},
            )
            self._last_request_ts = time.monotonic()
            try:
                with urllib.request.urlopen(req, timeout=200) as resp:
                    body = resp.read().decode("utf-8")
                parsed = json.loads(body)
                if "remark" in parsed:
                    if attempt < MAX_RETRIES:
                        print(
                            f"Overpass remark ({parsed['remark']}); waiting {RETRY_WAIT_S}s before retry {attempt + 1}/{MAX_RETRIES}...",
                            file=sys.stderr,
                        )
                        time.sleep(RETRY_WAIT_S)
                        continue
                    raise RuntimeError(f"Overpass query failed with remark: {parsed['remark']}")
                return parsed
            except urllib.error.HTTPError as e:
                if e.code in (429, 502, 503, 504) and attempt < MAX_RETRIES:
                    print(
                        f"Overpass HTTP {e.code}; waiting {RETRY_WAIT_S}s before retry {attempt + 1}/{MAX_RETRIES}...",
                        file=sys.stderr,
                    )
                    time.sleep(RETRY_WAIT_S)
                    continue
                raise
            except urllib.error.URLError as e:
                if attempt < MAX_RETRIES:
                    print(
                        f"Overpass URLError ({e}); waiting {RETRY_WAIT_S}s before retry {attempt + 1}/{MAX_RETRIES}...",
                        file=sys.stderr,
                    )
                    time.sleep(RETRY_WAIT_S)
                    continue
                raise
        raise RuntimeError("Unreachable")

    def get_cached_or_fetch(self, cache_names: List[str], query: str) -> Dict[str, Any]:
        for name in cache_names:
            path = os.path.join(self.cache_dir, name)
            if os.path.isfile(path):
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)

        data = self._query_overpass(query)
        primary_path = os.path.join(self.cache_dir, cache_names[0])
        tmp_path = primary_path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp_path, primary_path)
        return data

    def fetch_boundary(self, place: Dict[str, Any]) -> Dict[str, Any]:
        b_type, b_id = parse_boundary_spec(place["osm_boundary"])
        slug = place["id"].replace(":", "_")
        cache_names = [f"{b_type}{b_id}_boundary.json", f"{slug}_boundary.json"]
        osm_kw = "rel" if b_type == "r" else "way"
        query = f'[out:json][timeout:180][date:"{PINNED_DATE}"];\n{osm_kw}({b_id});\nout geom;\n'
        return self.get_cached_or_fetch(cache_names, query)

    def fetch_city_rule1(self, place: Dict[str, Any]) -> Dict[str, Any]:
        b_type, b_id = parse_boundary_spec(place["osm_boundary"])
        slug = place["id"].replace(":", "_")
        cache_names = [f"{b_type}{b_id}_rule1.json", f"{slug}_rule1.json"]
        query = (
            f'[out:json][timeout:180][date:"{PINNED_DATE}"];\n'
            f"rel({b_id}); map_to_area->.city;\n"
            f"(\n"
            f'  rel(area.city)["boundary"="administrative"]["admin_level"="10"];\n'
            f'  way(area.city)["place"="neighbourhood"];\n'
            f'  way(area.city)["place"="suburb"];\n'
            f'  way(area.city)["place"="quarter"];\n'
            f'  rel(area.city)["place"="neighbourhood"];\n'
            f'  rel(area.city)["place"="suburb"];\n'
            f'  rel(area.city)["place"="quarter"];\n'
            f");\n"
            f"out geom;\n"
        )
        return self.get_cached_or_fetch(cache_names, query)

    def fetch_city_rule2(self, place: Dict[str, Any]) -> Dict[str, Any]:
        b_type, b_id = parse_boundary_spec(place["osm_boundary"])
        slug = place["id"].replace(":", "_")
        cache_names = [f"{b_type}{b_id}_rule2.json", f"{slug}_rule2.json"]
        query = (
            f'[out:json][timeout:180][date:"{PINNED_DATE}"];\n'
            f"rel({b_id}); map_to_area->.city;\n"
            f"(\n"
            f'  node(area.city)["place"="neighbourhood"];\n'
            f'  node(area.city)["place"="suburb"];\n'
            f'  node(area.city)["place"="quarter"];\n'
            f");\n"
            f"out;\n"
        )
        return self.get_cached_or_fetch(cache_names, query)


# ---------------------------------------------------------------------------
# Geometry & Ring Stitching (matches region_converter.gd)
# ---------------------------------------------------------------------------


def _dist_sq(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    return dx * dx + dy * dy


def stitch_ways_to_rings(
    way_segments: List[List[Tuple[float, float]]],
) -> List[List[Tuple[float, float]]]:
    closed_rings: List[List[Tuple[float, float]]] = []
    open_chains: List[List[Tuple[float, float]]] = []

    for pts in way_segments:
        if len(pts) < 2:
            continue
        if _dist_sq(pts[0], pts[-1]) < 1e-4 and len(pts) >= 3:
            closed_rings.append(list(pts))
        else:
            open_chains.append(list(pts))

    while open_chains:
        chain = open_chains.pop(0)
        progress = True
        while progress and open_chains:
            progress = False
            if _dist_sq(chain[0], chain[-1]) < 1e-4 and len(chain) >= 3:
                break

            c_start = chain[0]
            c_end = chain[-1]

            for i, next_seg in enumerate(open_chains):
                n_start = next_seg[0]
                n_end = next_seg[-1]

                if _dist_sq(c_end, n_start) < 1e-3:
                    chain.extend(next_seg[1:])
                    open_chains.pop(i)
                    progress = True
                    break
                elif _dist_sq(c_end, n_end) < 1e-3:
                    chain.extend(reversed(next_seg[:-1]))
                    open_chains.pop(i)
                    progress = True
                    break
                elif _dist_sq(c_start, n_end) < 1e-3:
                    chain = list(next_seg[:-1]) + chain
                    open_chains.pop(i)
                    progress = True
                    break
                elif _dist_sq(c_start, n_start) < 1e-3:
                    chain = list(reversed(next_seg[1:])) + chain
                    open_chains.pop(i)
                    progress = True
                    break

        if len(chain) >= 3:
            if _dist_sq(chain[0], chain[-1]) >= 1e-4:
                chain.append(chain[0])
            closed_rings.append(chain)

    return closed_rings


def polygon_area(ring: List[Tuple[float, float]]) -> float:
    n = len(ring)
    if n < 3:
        return 0.0
    a = 0.0
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        a += x1 * y2 - x2 * y1
    return abs(a) * 0.5


def ring_contains_point(ring: List[Tuple[float, float]], px: float, py: float) -> bool:
    n = len(ring)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        denom = yj - yi
        if abs(denom) < 1e-9:
            denom = 1e-9
        if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / denom + xi):
            inside = not inside
        j = i
    return inside


def multipolygon_contains_point(
    rings: List[List[Tuple[float, float]]], px: float, py: float
) -> bool:
    """Even-odd rule across all stitched rings (outers and inners)."""
    inside = False
    for r in rings:
        if ring_contains_point(r, px, py):
            inside = not inside
    return inside


def extract_element_rings_and_area(
    el: Dict[str, Any],
    node_lookup: Optional[Dict[int, Tuple[float, float]]] = None,
    way_lookup: Optional[Dict[int, List[int]]] = None,
) -> Tuple[List[List[Tuple[float, float]]], float]:
    """
    Extract closed Web-Mercator rings (outers + inners) from an Overpass relation or way element,
    and compute its total geometric area (outer ring areas minus inner ring areas).
    """
    etype = el.get("type")
    if etype == "way":
        geom = el.get("geometry", [])
        pts: List[Tuple[float, float]] = []
        if geom:
            for pt in geom:
                if pt and "lat" in pt and "lon" in pt:
                    pts.append(grid.latlon_to_wm(float(pt["lat"]), float(pt["lon"])))
        elif node_lookup and "nodes" in el:
            for nid in el["nodes"]:
                if nid in node_lookup:
                    lat, lon = node_lookup[nid]
                    pts.append(grid.latlon_to_wm(lat, lon))
        rings = stitch_ways_to_rings([pts]) if len(pts) >= 3 else []
        area = sum(polygon_area(r) for r in rings)
        return rings, area

    elif etype == "relation":
        outer_ways: List[List[Tuple[float, float]]] = []
        inner_ways: List[List[Tuple[float, float]]] = []
        for m in el.get("members", []):
            if m.get("type") != "way":
                continue
            geom = m.get("geometry", [])
            pts = []
            if geom:
                for pt in geom:
                    if pt and "lat" in pt and "lon" in pt:
                        pts.append(grid.latlon_to_wm(float(pt["lat"]), float(pt["lon"])))
            elif way_lookup and node_lookup and int(m.get("ref", -1)) in way_lookup:
                for nid in way_lookup[int(m["ref"])]:
                    if nid in node_lookup:
                        lat, lon = node_lookup[nid]
                        pts.append(grid.latlon_to_wm(lat, lon))
            if len(pts) < 2:
                continue
            role = str(m.get("role", ""))
            if role == "inner":
                inner_ways.append(pts)
            else:
                outer_ways.append(pts)

        outer_rings = stitch_ways_to_rings(outer_ways)
        inner_rings = stitch_ways_to_rings(inner_ways)
        all_rings = outer_rings + inner_rings
        area = max(
            0.0,
            sum(polygon_area(r) for r in outer_rings)
            - sum(polygon_area(r) for r in inner_rings),
        )
        return all_rings, area

    return [], 0.0


def find_inside_cells(rings: List[List[Tuple[float, float]]]) -> List[Tuple[int, int]]:
    """
    Find all cells (cx, cy) whose centre ((cx + 0.5) * 256, (cy + 0.5) * 256)
    is inside the multipolygon `rings` under the even-odd rule.
    Uses scanline intersection per row `cy`, which is 100% mathematically identical
    to calling `multipolygon_contains_point` for each cell centre.
    """
    if not rings:
        return []

    min_x = float("inf")
    min_y = float("inf")
    max_x = float("-inf")
    max_y = float("-inf")

    # Pre-extract non-horizontal edges with their y-spans
    edges: List[Tuple[float, float, float, float, float]] = []
    for r in rings:
        n = len(r)
        if n < 3:
            continue
        j = n - 1
        for i in range(n):
            xi, yi = r[i]
            xj, yj = r[j]
            if xi < min_x:
                min_x = xi
            if xi > max_x:
                max_x = xi
            if yi < min_y:
                min_y = yi
            if yi > max_y:
                max_y = yi
            if yi != yj:
                denom = yj - yi
                if abs(denom) < 1e-9:
                    denom = 1e-9
                edges.append((xi, yi, xj, yj, denom))
            j = i

    if min_x > max_x or min_y > max_y:
        return []

    min_cx, min_cy = grid.wm_to_cell(min_x, min_y)
    max_cx, max_cy = grid.wm_to_cell(max_x, max_y)

    inside_cells: List[Tuple[int, int]] = []
    cell_wm = grid.CELL_WM

    for cy in range(min_cy, max_cy + 1):
        py = (float(cy) + 0.5) * cell_wm
        x_crossings: List[float] = []
        for xi, yi, xj, yj, denom in edges:
            if (yi > py) != (yj > py):
                x_cross = (xj - xi) * (py - yi) / denom + xi
                x_crossings.append(x_cross)
        if not x_crossings:
            continue
        x_crossings.sort()
        total_cross = len(x_crossings)
        # A point px has `px < x_cross` for `total_cross - bisect_right(x_crossings, px)` crossings
        for cx in range(min_cx, max_cx + 1):
            px = (float(cx) + 0.5) * cell_wm
            idx = bisect.bisect_right(x_crossings, px)
            if (total_cross - idx) % 2 == 1:
                inside_cells.append((cx, cy))

    return inside_cells


def compute_threshold(num_areas: int) -> int:
    """Decision 22: T = 1 if 1 neighbourhood, else clamp(ceil(0.10 * n), 2, 5)."""
    if num_areas <= 1:
        return 1
    return min(5, max(2, int(math.ceil(0.10 * num_areas))))


def encode_rows(
    cell_to_area_idx: Dict[Tuple[int, int], int],
) -> List[List[int]]:
    """
    Encode (cx, cy) -> area_index into run-length rows:
    [ [cy, cx0, len, area_index, cx0, len, area_index, ...], ... ]
    Sorted by cy ascending, then cx0 ascending.
    """
    by_row: Dict[int, List[Tuple[int, int]]] = {}
    for (cx, cy), a_idx in cell_to_area_idx.items():
        by_row.setdefault(cy, []).append((cx, a_idx))

    rows_out: List[List[int]] = []
    for cy in sorted(by_row.keys()):
        row_cells = sorted(by_row[cy], key=lambda item: item[0])
        if not row_cells:
            continue
        row_entry: List[int] = [cy]
        run_cx0, run_aidx = row_cells[0]
        run_len = 1
        for cx, a_idx in row_cells[1:]:
            if cx == run_cx0 + run_len and a_idx == run_aidx:
                run_len += 1
            else:
                row_entry.extend([run_cx0, run_len, run_aidx])
                run_cx0 = cx
                run_aidx = a_idx
                run_len = 1
        row_entry.extend([run_cx0, run_len, run_aidx])
        rows_out.append(row_entry)

    return rows_out


def decode_rows(rows: List[List[int]]) -> Dict[Tuple[int, int], int]:
    """Inverse of encode_rows for round-trip verification."""
    out: Dict[Tuple[int, int], int] = {}
    for r in rows:
        cy = r[0]
        i = 1
        while i < len(r):
            cx0 = r[i]
            length = r[i + 1]
            a_idx = r[i + 2]
            for dx in range(length):
                out[(cx0 + dx, cy)] = a_idx
            i += 3
    return out


def build_place_entry(
    place: Dict[str, Any],
    client: OverpassClient,
    excluded_cells: Optional[Set[Tuple[int, int]]] = None,
) -> Tuple[Dict[str, Any], Dict[str, int]]:
    """
    Build one place's pack entry and return (entry_dict, stats_by_rule).
    """
    pid = place["id"]
    pkind = place["kind"]
    pname = place["name"]
    pregion = place["region"]
    waypost_raw = place.get("waypost", {})
    waypost = {
        "lat": float(waypost_raw["lat"]),
        "lon": float(waypost_raw["lon"]),
    }

    b_data = client.fetch_boundary(place)
    target_el = validate_boundary_element(place, b_data)
    node_lookup = {
        int(e["id"]): (float(e["lat"]), float(e["lon"]))
        for e in b_data.get("elements", [])
        if e.get("type") == "node" and "lat" in e and "lon" in e
    }
    way_lookup = {
        int(e["id"]): [int(nid) for nid in e.get("nodes", [])]
        for e in b_data.get("elements", [])
        if e.get("type") == "way" and "nodes" in e
    }
    boundary_rings, _ = extract_element_rings_and_area(target_el, node_lookup, way_lookup)
    if not boundary_rings:
        raise ValueError(f"Place {pid} boundary produced no closed rings")

    inside_cells = find_inside_cells(boundary_rings)
    if excluded_cells:
        inside_cells = [c for c in inside_cells if c not in excluded_cells]
    if not inside_cells:
        raise ValueError(f"Place {pid} boundary contains 0 cells")

    cxs = [c[0] for c in inside_cells]
    cys = [c[1] for c in inside_cells]
    bbox = [min(cxs), min(cys), max(cxs), max(cys)]

    stats = {"polygon_areas": 0, "point_areas": 0, "grid_areas": 0, "total_cells": len(inside_cells)}

    if pkind == "site":
        areas = [{"key": pid, "name": pname}]
        cell_to_area_idx = {c: 0 for c in inside_cells}
        rows = encode_rows(cell_to_area_idx)
        entry = {
            "id": pid,
            "kind": "site",
            "name": pname,
            "region": pregion,
            "waypost": waypost,
            "threshold": 1,
            "bbox": bbox,
            "areas": areas,
            "rows": rows,
        }
        return entry, stats

    # City neighbourhood assignment (famous-places plan §8.2)
    r1_data = client.fetch_city_rule1(place)
    r2_data = client.fetch_city_rule2(place)

    r1_node_lookup = {
        int(e["id"]): (float(e["lat"]), float(e["lon"]))
        for e in r1_data.get("elements", [])
        if e.get("type") == "node" and "lat" in e and "lon" in e
    }

    # Filter Rule-1 polygons:
    # Named boundary=administrative with admin_level=10 (NEVER 9),
    # or named closed way/relation with place=neighbourhood|suburb|quarter.
    rule1_polys: List[Dict[str, Any]] = []
    for el in r1_data.get("elements", []):
        etype = el.get("type")
        if etype not in ("relation", "way"):
            continue
        tags = el.get("tags", {})
        name = str(tags.get("name", "")).strip()
        if not name:
            continue
        is_admin10 = (
            tags.get("boundary") == "administrative"
            and str(tags.get("admin_level", "")).strip() == "10"
        )
        is_place_poly = str(tags.get("place", "")).strip() in (
            "neighbourhood",
            "suburb",
            "quarter",
        )
        if not (is_admin10 or is_place_poly):
            continue

        rings, area = extract_element_rings_and_area(el, r1_node_lookup)
        if not rings or area <= 0.0:
            continue

        # Precompute bounding box of Rule-1 polygon for fast culling
        r_min_x = min(pt[0] for r in rings for pt in r)
        r_max_x = max(pt[0] for r in rings for pt in r)
        r_min_y = min(pt[1] for r in rings for pt in r)
        r_max_y = max(pt[1] for r in rings for pt in r)

        osm_id = int(el["id"])
        prefix = "r" if etype == "relation" else "w"
        rule1_polys.append(
            {
                "key": f"osm:{prefix}{osm_id}",
                "osm_id": osm_id,
                "type_rank": 0 if etype == "relation" else 1,
                "name": name,
                "rings": rings,
                "area": area,
                "bbox_wm": (r_min_x, r_min_y, r_max_x, r_max_y),
            }
        )

    # Sort Rule-1 polygons by (area ascending, osm_id ascending, type_rank ascending)
    rule1_polys.sort(key=lambda p: (p["area"], p["osm_id"], p["type_rank"]))

    # Filter Rule-2 points:
    # Named place=neighbourhood|suburb|quarter node inside the city that lies in no Rule-1 polygon.
    rule2_nodes: List[Dict[str, Any]] = []
    seen_node_ids: Set[int] = set()
    for el in r2_data.get("elements", []):
        if el.get("type") != "node":
            continue
        nid = int(el["id"])
        if nid in seen_node_ids:
            continue
        tags = el.get("tags", {})
        name = str(tags.get("name", "")).strip()
        place_tag = str(tags.get("place", "")).strip()
        if not name or place_tag not in ("neighbourhood", "suburb", "quarter"):
            continue
        if "lat" not in el or "lon" not in el:
            continue
        wx, wy = grid.latlon_to_wm(float(el["lat"]), float(el["lon"]))
        if not multipolygon_contains_point(boundary_rings, wx, wy):
            continue
        in_r1 = False
        for r1 in rule1_polys:
            bx0, by0, bx1, by1 = r1["bbox_wm"]
            if bx0 <= wx <= bx1 and by0 <= wy <= by1:
                if multipolygon_contains_point(r1["rings"], wx, wy):
                    in_r1 = True
                    break
        if in_r1:
            continue
        seen_node_ids.add(nid)
        rule2_nodes.append(
            {
                "key": f"osm:n{nid}",
                "osm_id": nid,
                "name": name,
                "wm_x": wx,
                "wm_y": wy,
            }
        )

    rule2_nodes.sort(key=lambda n: n["osm_id"])

    # Assign each inside cell
    cell_WM = grid.CELL_WM
    cell_key_map: Dict[Tuple[int, int], str] = {}
    area_names: Dict[str, str] = {}
    area_rules: Dict[str, str] = {}

    # Precompute inside cells of each Rule-1 polygon using fast scanline
    r1_cell_sets: List[Set[Tuple[int, int]]] = [
        set(find_inside_cells(r1["rings"])) for r1 in rule1_polys
    ]

    for cx, cy in inside_cells:
        assigned_key = ""
        assigned_name = ""
        assigned_rule = ""

        # Rule 1: smallest polygon containing cell centre (rule1_polys is already sorted by smallest area, then lower id)
        for idx_r1, r1 in enumerate(rule1_polys):
            if (cx, cy) in r1_cell_sets[idx_r1]:
                assigned_key = r1["key"]
                assigned_name = r1["name"]
                assigned_rule = "polygon"
                break

        # Rule 2: nearest Rule-2 point (WM-m distance, ties to lower id)
        if not assigned_key and rule2_nodes:
            px = (float(cx) + 0.5) * cell_WM
            py = (float(cy) + 0.5) * cell_WM
            best_d2 = float("inf")
            best_node = None
            for n in rule2_nodes:
                dx = n["wm_x"] - px
                dy = n["wm_y"] - py
                d2 = dx * dx + dy * dy
                if d2 < best_d2 - 1e-6 or (
                    abs(d2 - best_d2) <= 1e-6
                    and (best_node is None or n["osm_id"] < best_node["osm_id"])
                ):
                    best_d2 = d2
                    best_node = n
            if best_node is not None:
                assigned_key = best_node["key"]
                assigned_name = best_node["name"]
                assigned_rule = "point"

        # Rule 3: 4x4 cell district grid:<city id>:<floor(cx/4)>:<floor(cy/4)>
        if not assigned_key:
            gx = int(math.floor(float(cx) / 4.0))
            gy = int(math.floor(float(cy) / 4.0))
            assigned_key = f"grid:{pid}:{gx}:{gy}"
            assigned_name = ""
            assigned_rule = "grid"

        cell_key_map[(cx, cy)] = assigned_key
        area_names[assigned_key] = assigned_name
        area_rules[assigned_key] = assigned_rule

    sorted_keys = sorted(area_names.keys())
    key_to_idx = {k: i for i, k in enumerate(sorted_keys)}
    areas = [{"key": k, "name": area_names[k]} for k in sorted_keys]

    for k in sorted_keys:
        r_kind = area_rules[k]
        if r_kind == "polygon":
            stats["polygon_areas"] += 1
        elif r_kind == "point":
            stats["point_areas"] += 1
        else:
            stats["grid_areas"] += 1

    cell_to_area_idx = {c: key_to_idx[k] for c, k in cell_key_map.items()}
    rows = encode_rows(cell_to_area_idx)
    threshold = compute_threshold(len(areas))

    entry = {
        "id": pid,
        "kind": "city",
        "name": pname,
        "region": pregion,
        "waypost": waypost,
        "threshold": threshold,
        "bbox": bbox,
        "areas": areas,
        "rows": rows,
    }
    return entry, stats


def load_places_config(config_path: str) -> List[Dict[str, Any]]:
    with open(config_path, "r", encoding="utf-8") as f:
        parsed = json.load(f)
    if isinstance(parsed, dict) and "places" in parsed:
        return parsed["places"]
    if isinstance(parsed, list):
        return parsed
    raise ValueError(f"Unexpected config structure in {config_path}")


def serialize_pack_gzip(pack_obj: Dict[str, Any]) -> bytes:
    """Canonical JSON (sorted keys, no whitespace), gzipped with mtime=0."""
    canonical_json = json.dumps(
        pack_obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    buf = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buf, mtime=0, compresslevel=9) as gz:
        gz.write(canonical_json)
    return buf.getvalue()


# Human-approved site carve-outs where a site's islands/enclave lie inside a city's marine boundary (§1.3).
APPROVED_SITE_CARVEOUTS: Dict[str, List[str]] = {
    "city:boston": ["site:boston-harbor-islands"],
}


def build_pack(
    config_path: str,
    cache_dir: str,
    offline: bool = False,
) -> Tuple[Dict[str, Any], Dict[str, Dict[str, int]]]:
    """
    Build the full pack dictionary and per-place rule stats from `config_path` and `cache_dir`.
    Raises RuntimeError if any cell belongs to two places.
    """
    raw_places = load_places_config(config_path)
    client = OverpassClient(cache_dir=cache_dir, offline=offline)

    pack_places: List[Dict[str, Any]] = []
    all_stats: Dict[str, Dict[str, int]] = {}
    global_cell_owner: Dict[Tuple[int, int], str] = {}

    eligible = [p for p in raw_places if p.get("kind", "") in ("city", "site")]
    places_by_id = {p["id"]: p for p in eligible}
    total = len(eligible)
    for idx, place in enumerate(eligible, 1):
        pid = place["id"]
        excluded: Set[Tuple[int, int]] = set()
        for carve_sid in APPROVED_SITE_CARVEOUTS.get(pid, []):
            if carve_sid in places_by_id:
                s_place = places_by_id[carve_sid]
                s_bdata = client.fetch_boundary(s_place)
                s_el = validate_boundary_element(s_place, s_bdata)
                s_rings, _ = extract_element_rings_and_area(s_el)
                excluded.update(find_inside_cells(s_rings))
        entry, stats = build_place_entry(place, client, excluded_cells=excluded or None)
        print(
            f"[{idx}/{total}] {pid}: {len(entry['areas'])} areas, {stats['total_cells']} cells (T={entry['threshold']})",
            flush=True,
        )
        decoded = decode_rows(entry["rows"])
        for cell in decoded.keys():
            if cell in global_cell_owner:
                other_pid = global_cell_owner[cell]
                raise RuntimeError(
                    f"Cell overlap detected at {cell} between {other_pid} and {pid}"
                )
            global_cell_owner[cell] = pid

        pack_places.append(entry)
        all_stats[pid] = stats

    pack_obj = {
        "pack_version": PACK_VERSION,
        "snapshot": SNAPSHOT_ID,
        "attribution": ATTRIBUTION,
        "places": pack_places,
    }
    return pack_obj, all_stats


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default_config = os.path.join(repo_root, "game", "config", "famous_places.json")
    default_cache = os.path.expanduser("~/.cache/tenth_spring/overpass")
    default_out = os.path.join(repo_root, "game", "data", "places_pack_v1.json.gz")
    default_sha = os.path.join(repo_root, "game", "data", "places_pack_v1.sha256")
    default_companion = os.path.join(repo_root, "companion", "assets", "places_pack_v1.json.gz")

    parser = argparse.ArgumentParser(description="Build Tenth Spring places pack v1.")
    parser.add_argument("--config", default=default_config, help="Path to famous_places.json")
    parser.add_argument("--cache-dir", default=default_cache, help="Overpass response cache dir")
    parser.add_argument("--out", default=default_out, help="Output .json.gz path")
    parser.add_argument("--sha256-out", default=default_sha, help="Output .sha256 path (empty to skip)")
    parser.add_argument(
        "--companion-out",
        default=default_companion,
        help="Companion asset copy path (empty to skip)",
    )
    parser.add_argument("--offline", action="store_true", help="Do not make network requests")
    args = parser.parse_args()

    try:
        pack_obj, all_stats = build_pack(
            config_path=args.config,
            cache_dir=args.cache_dir,
            offline=args.offline,
        )
    except Exception as exc:
        print(f"[BUILD PLACES PACK FAILED] {exc}", file=sys.stderr)
        return 1

    gz_bytes = serialize_pack_gzip(pack_obj)
    gz_size = len(gz_bytes)
    if gz_size > MAX_GZIP_BYTES:
        print(
            f"[BUILD PLACES PACK FAILED] Gzipped size {gz_size} bytes exceeds 4 MiB limit ({MAX_GZIP_BYTES} bytes)",
            file=sys.stderr,
        )
        return 1

    sha256_hex = hashlib.sha256(gz_bytes).hexdigest()

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "wb") as f:
        f.write(gz_bytes)

    if args.sha256_out:
        os.makedirs(os.path.dirname(os.path.abspath(args.sha256_out)), exist_ok=True)
        with open(args.sha256_out, "w", encoding="utf-8") as f:
            f.write(f"{sha256_hex}  places_pack_v1.json.gz\n")

    if args.companion_out:
        os.makedirs(os.path.dirname(os.path.abspath(args.companion_out)), exist_ok=True)
        shutil.copyfile(args.out, args.companion_out)

    print(
        f"[BUILD PLACES PACK OK] {len(pack_obj['places'])} places, "
        f"{gz_size} bytes ({gz_size / (1024 * 1024):.3f} MiB), sha256={sha256_hex}"
    )
    if "city:washington-dc" in all_stats:
        dc_entry = next(p for p in pack_obj["places"] if p["id"] == "city:washington-dc")
        dc_st = all_stats["city:washington-dc"]
        print(
            f"  DC summary: {len(dc_entry['areas'])} areas, T={dc_entry['threshold']}, "
            f"polygon={dc_st['polygon_areas']}, point={dc_st['point_areas']}, grid={dc_st['grid_areas']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
