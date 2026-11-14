#!/usr/bin/env python3
"""
tools/test_check_neighbourhoods.py — Unit and falsification suite for check_neighbourhoods.py (Items 47, 53)
Contract: docs/implementation_plan_dc_trial.md §1.4, §9, §10.3, §10.12; docs/agent_execution_guide.md §3
"""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKER_SCRIPT = os.path.join(REPO_ROOT, "tools", "check_neighbourhoods.py")
CANONICAL_CONFIG = os.path.join(REPO_ROOT, "game", "config", "neighbourhoods.json")


def _run_checker(config_path: str):
    res = subprocess.run(
        [sys.executable, "-I", CHECKER_SCRIPT, config_path],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    out = ((res.stdout or "") + (res.stderr or "")).strip()
    return res.returncode, out


def _build_routes_fixture(base_data: dict) -> dict:
    """Build a valid city-with-routes fixture (ready=false) from canonical anchors + contract §7.5–§7.6."""
    data = copy.deepcopy(base_data)
    city = data["cities"][0]
    city["ready"] = False
    city["camp"]["cells"] = [2, 2]

    hood_layout = {
        "hood:washington-dc:national-mall": ([-6, -4], [5, 4]),
        "hood:washington-dc:tidal-basin": ([-7, -10], [4, 4]),
        "hood:washington-dc:dupont-circle": ([-7, 2], [4, 4]),
        "hood:washington-dc:capitol-hill": ([4, -4], [5, 4]),
        "hood:washington-dc:union-station": ([4, 2], [4, 4]),
        "hood:washington-dc:georgetown": ([-16, 4], [4, 4]),
        "hood:washington-dc:woodley-park": ([-8, 10], [4, 4]),
        "hood:washington-dc:lincoln-memorial": ([-14, -4], [5, 4]),
    }
    for h in city["neighbourhoods"]:
        at, cells = hood_layout[h["id"]]
        h["at"] = list(at)
        h["cells"] = list(cells)

    city["routes"] = [
        {
            "id": "route:washington-dc:monument-grounds",
            "name": "Monument Grounds",
            "ends": ["hood:washington-dc:national-mall", "hood:washington-dc:tidal-basin"],
            "legs": [{"at": [-5, -6], "cells": [1, 2], "map": "washington-dc/routes/monument-grounds.json"}],
            "zone": "parkland",
            "ruin_level": "near",
            "calm": False,
            "landmarks": [{"name": "the Sylvan Theater", "feature": "stage", "sign": "Sylvan Theater"}],
        },
        {
            "id": "route:washington-dc:pennsylvania-avenue",
            "name": "Pennsylvania Avenue",
            "ends": ["hood:washington-dc:national-mall", "hood:washington-dc:capitol-hill"],
            "legs": [{"at": [-1, -3], "cells": [5, 1], "map": "washington-dc/routes/pennsylvania-avenue.json"}],
            "zone": "downtown",
            "ruin_level": "near",
            "calm": False,
            "landmarks": [{"name": "the National Archives", "feature": "building", "sign": "National Archives"}],
        },
        {
            "id": "route:washington-dc:constitution-gardens",
            "name": "Constitution Gardens",
            "ends": ["hood:washington-dc:national-mall", "hood:washington-dc:lincoln-memorial"],
            "legs": [{"at": [-9, -2], "cells": [3, 1], "map": "washington-dc/routes/constitution-gardens.json"}],
            "zone": "parkland",
            "ruin_level": "near",
            "calm": True,
            "landmarks": [{"name": "Constitution Gardens Pond", "feature": "pond", "sign": "Constitution Gardens Pond"}],
        },
        {
            "id": "route:washington-dc:west-potomac-park",
            "name": "West Potomac Park",
            "ends": ["hood:washington-dc:tidal-basin", "hood:washington-dc:lincoln-memorial"],
            "legs": [
                {"at": [-10, -7], "cells": [3, 1], "map": "washington-dc/routes/west-potomac-park-1.json"},
                {"at": [-10, -6], "cells": [1, 2], "map": "washington-dc/routes/west-potomac-park-2.json"},
            ],
            "zone": "waterfront",
            "ruin_level": "near",
            "calm": True,
            "landmarks": [{"name": "West Potomac Park", "feature": "park", "sign": "West Potomac Park"}],
        },
        {
            "id": "route:washington-dc:upper-senate-park",
            "name": "Upper Senate Park",
            "ends": ["hood:washington-dc:capitol-hill", "hood:washington-dc:union-station"],
            "legs": [{"at": [6, 0], "cells": [1, 2], "map": "washington-dc/routes/upper-senate-park.json"}],
            "zone": "institutional",
            "ruin_level": "near",
            "calm": False,
            "landmarks": [{"name": "Upper Senate Park", "feature": "park", "sign": "Upper Senate Park"}],
        },
        {
            "id": "route:washington-dc:q-street",
            "name": "Q Street",
            "ends": ["hood:washington-dc:dupont-circle", "hood:washington-dc:georgetown"],
            "legs": [{"at": [-12, 4], "cells": [5, 1], "map": "washington-dc/routes/q-street.json"}],
            "zone": "residential",
            "ruin_level": "mid",
            "calm": False,
            "landmarks": [{"name": "Buffalo Bridge", "feature": "bridge", "sign": "Buffalo Bridge"}],
        },
        {
            "id": "route:washington-dc:connecticut-avenue",
            "name": "Connecticut Avenue",
            "ends": ["hood:washington-dc:dupont-circle", "hood:washington-dc:woodley-park"],
            "legs": [{"at": [-6, 6], "cells": [1, 4], "map": "washington-dc/routes/connecticut-avenue.json"}],
            "zone": "residential",
            "ruin_level": "mid",
            "calm": False,
            "landmarks": [{"name": "Taft Bridge", "feature": "bridge", "sign": "Taft Bridge"}],
        },
        {
            "id": "route:washington-dc:massachusetts-avenue",
            "name": "Massachusetts Avenue",
            "ends": ["hood:washington-dc:dupont-circle", "hood:washington-dc:union-station"],
            "legs": [{"at": [-3, 4], "cells": [7, 1], "map": "washington-dc/routes/massachusetts-avenue.json"}],
            "zone": "downtown",
            "ruin_level": "mid",
            "calm": False,
            "landmarks": [
                {"name": "Thomas Circle", "feature": "circle", "sign": "Thomas Circle"},
                {"name": "Mount Vernon Square", "feature": "square", "sign": "Mount Vernon Square"},
            ],
        },
        {
            "id": "route:washington-dc:rock-creek-trail",
            "name": "Rock Creek Trail",
            "ends": ["hood:washington-dc:georgetown", "hood:washington-dc:woodley-park"],
            "legs": [
                {"at": [-12, 7], "cells": [5, 1], "map": "washington-dc/routes/rock-creek-trail-1.json"},
                {"at": [-8, 8], "cells": [1, 2], "map": "washington-dc/routes/rock-creek-trail-2.json"},
            ],
            "zone": "wilds",
            "ruin_level": "far",
            "calm": False,
            "landmarks": [{"name": "Rock Creek", "feature": "creek", "sign": "Rock Creek"}],
        },
        {
            "id": "route:washington-dc:potomac-riverfront",
            "name": "Potomac Riverfront",
            "ends": ["hood:washington-dc:georgetown", "hood:washington-dc:lincoln-memorial"],
            "legs": [{"at": [-14, 0], "cells": [1, 4], "map": "washington-dc/routes/potomac-riverfront.json"}],
            "zone": "waterfront",
            "ruin_level": "mid",
            "calm": False,
            "landmarks": [
                {"name": "Kennedy Center", "feature": "building", "sign": "Kennedy Center"},
                {"name": "Potomac River", "feature": "river", "sign": "Potomac River"},
            ],
        },
    ]
    return data


class TestCheckNeighbourhoods(unittest.TestCase):
    def setUp(self):
        with open(CANONICAL_CONFIG, "r", encoding="utf-8") as f:
            self.valid_data = json.load(f)
        self.routes_data = _build_routes_fixture(self.valid_data)

    def _assert_fails_rule(self, mutated_data, rule_id: str):
        with tempfile.TemporaryDirectory() as tmpdir:
            cfg_path = os.path.join(tmpdir, "neighbourhoods.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                if isinstance(mutated_data, str):
                    f.write(mutated_data)
                else:
                    json.dump(mutated_data, f)
            code, out = _run_checker(cfg_path)
            self.assertEqual(
                code,
                1,
                f"Expected exit 1 for {rule_id}, got exit {code} with output: {out}",
            )
            expected_prefix = f"[CHECK NEIGHBOURHOODS FAIL] {rule_id}:"
            self.assertIn(
                expected_prefix,
                out,
                f"Expected '{expected_prefix}' in output, got: {out}",
            )

    def test_canonical_file_valid(self):
        code, out = _run_checker(CANONICAL_CONFIG)
        self.assertEqual(code, 0, f"Canonical file failed: {out}")
        self.assertEqual(
            out,
            "[CHECK NEIGHBOURHOODS OK] 1 cities, 8 neighbourhoods, 1 camps, 10 routes, 12 legs.",
        )

    def test_routes_fixture_valid(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            cfg_path = os.path.join(tmpdir, "neighbourhoods_routes.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(self.routes_data, f)
            code, out = _run_checker(cfg_path)
            self.assertEqual(code, 0, f"Routes fixture failed: {out}")
            self.assertEqual(
                out,
                "[CHECK NEIGHBOURHOODS OK] 1 cities, 8 neighbourhoods, 1 camps, 10 routes, 12 legs.",
            )

    def test_falsifying_N1_version_and_city_entry(self):
        mutated = copy.deepcopy(self.routes_data)
        mutated["version"] = 2
        self._assert_fails_rule(mutated, "N1")

    def test_falsifying_N2_neighbourhood_count(self):
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["neighbourhoods"].pop()
        self._assert_fails_rule(mutated, "N2")

    def test_falsifying_N3_id_format_and_uniqueness(self):
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["neighbourhoods"][0]["id"] = "hood:washington-dc:National_Mall"
        self._assert_fails_rule(mutated, "N3")

    def test_falsifying_N4_role_counts(self):
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:union-station":
                h["role"] = "gateway"
        self._assert_fails_rule(mutated, "N4")

    def test_falsifying_N5_gateways_nearest_waypost(self):
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:capitol-hill":
                h["role"] = "inner"
            elif h["id"] == "hood:washington-dc:union-station":
                h["role"] = "gateway"
        self._assert_fails_rule(mutated, "N5")

    def test_falsifying_N6_block_cell_dimensions(self):
        # Decision 58 sizes: neighbourhoods must be [4, 3], [4, 4], or [5, 4]; camp [2, 2].
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["neighbourhoods"][2]["cells"] = [2, 2]
        self._assert_fails_rule(mutated, "N6")

    def test_falsifying_N9_borders_symmetric_and_reachable(self):
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:woodley-park":
                h["borders"] = []
            else:
                h["borders"] = [
                    b for b in h["borders"] if b != "hood:washington-dc:woodley-park"
                ]
        self._assert_fails_rule(mutated, "N9")

    def test_falsifying_N10_zone_haunt_and_ruin_level(self):
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["neighbourhoods"][2]["zone"] = "suburb"
        self._assert_fails_rule(mutated, "N10")

    def test_falsifying_N11_landmarks_schema(self):
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:tidal-basin":
                h["landmarks"] = [h["landmarks"][0]]
        self._assert_fails_rule(mutated, "N11")

    def test_falsifying_N12_city_interiors_bijection(self):
        mutated = copy.deepcopy(self.routes_data)
        del mutated["cities"][0]["neighbourhoods"][0]["landmarks"][0]["interior"]
        self._assert_fails_rule(mutated, "N12")

    def test_falsifying_N13_main_quest_schema(self):
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:dupont-circle":
                h["main_quest"]["pattern"] = "time_of_day"
        self._assert_fails_rule(mutated, "N13")

    def test_falsifying_N14_ready_flag_and_maps_present(self):
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["ready"] = True
        mutated["cities"][0]["camp"]["map"] = "washington-dc/missing-falsifier.json"
        self._assert_fails_rule(mutated, "N14")

    def test_falsifying_L1_at_placement_and_overlap(self):
        # Camp may not carry 'at' (and blocks may not overlap).
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["camp"]["at"] = [0, 0]
        self._assert_fails_rule(mutated, "L1")

    def test_falsifying_L2_non_chain_blocks_touching(self):
        # pennsylvania-avenue at [-1, -1] [5, 1] still connects national-mall [-6..-2, -4..-1]
        # to capitol-hill [4..8, -4..-1], while touching camp [0..1, 0..1] along y=-1 vs y=0 (Chebyshev distance 1).
        mutated = copy.deepcopy(self.routes_data)
        for r in mutated["cities"][0]["routes"]:
            if r["id"] == "route:washington-dc:pennsylvania-avenue":
                r["legs"][0]["at"] = [-1, -1]
        self._assert_fails_rule(mutated, "L2")

    def test_falsifying_L3_leg_shape_count_and_no_camp(self):
        # A leg must be [n, 1] or [1, n] (not 2 cells thick).
        mutated = copy.deepcopy(self.routes_data)
        for r in mutated["cities"][0]["routes"]:
            if r["id"] == "route:washington-dc:q-street":
                r["legs"][0]["cells"] = [5, 2]
        self._assert_fails_rule(mutated, "L3")

    def test_falsifying_L4_chain_shared_edges_and_right_angle(self):
        # Shift monument-grounds leg from [-5, -6] to [-3, -6]:
        # It shares an edge with national-mall [-6..-2, -4..-1] at (-3,-4), stays >= 2 from non-chain blocks,
        # and touches tidal-basin [-7..-4, -10..-7] ONLY at a corner (-3,-6) vs (-4,-7) instead of sharing an edge.
        mutated = copy.deepcopy(self.routes_data)
        for r in mutated["cities"][0]["routes"]:
            if r["id"] == "route:washington-dc:monument-grounds":
                r["legs"][0]["at"] = [-3, -6]
        self._assert_fails_rule(mutated, "L4")

    def test_falsifying_L5_route_compass_vs_real_anchors(self):
        # Reverse monument-grounds ends (tidal-basin -> national-mall) while swapping its leg order?
        # Wait: monument-grounds has 1 leg: if ends are [tidal-basin, national-mall], chain goes NORTH (from y=-7 to y=-4),
        # which ACTUALLY matches real anchors (tidal-basin 38.8822 -> national-mall 38.8895 is north)!
        # To violate L5 cleanly while keeping L1, L2, L3, L4, L6, L7, L8 all valid:
        # Place woodley-park SOUTH of dupont-circle? No, woodley-park connects to georgetown too.
        # Look at tidal-basin: it only connects to national-mall and lincoln-memorial!
        # Even simpler: swap anchors of union-station and capitol-hill? No, N5 checks gateway distances!
        # Look at woodley-park (inner, 4.15 km) and georgetown (inner, 3.81 km): neither is a gateway!
        # Wait: if we move woodley-park's `at`? No, if we keep woodley-park's real anchor (north of dupont-circle),
        # what if we move union-station (only borders dupont-circle and capitol-hill)?
        # Wait: look at monument-grounds (national-mall -> tidal-basin, real displacement is SOUTH: -0.81 km north, -0.21 km east).
        # Move tidal-basin NORTH of national-mall? No, west-potomac-park also touches tidal-basin.
        # Move BOTH woodley-park (`at`)? No: woodley-park only borders dupont-circle and georgetown!
        # Wait: why not change woodley-park's real `anchor` to a point far SOUTH of DC waypost (still > 2.05 km so N5 gateways stay identical!)?
        # Check N5: gateways are nearest 4 non-finale (< 2.05 km). A point 3.5 km SOUTH of waypost (38.8636, -77.0498) is > 2.05 km (stays inner -> N5 passes!),
        # AND real distance to dupont-circle (38.9096, -77.0434) is ~5.1 km SOUTH (so L5 checks compass FIRST before L6!).
        # Even better: pick an anchor for woodley-park due SOUTH of dupont-circle at ~2.3 km from dupont-circle AND > 2.1 km from waypost?
        # Wait: dupont-circle is 1.91 km NW of waypost. Any point 2.3 km EAST-SOUTH-EAST of dupont-circle at (38.895, -77.018)? No, that's 1.1 km from waypost.
        # Point 2.5 km WEST-SOUTH-WEST of dupont-circle: lat=38.8960, lon=-77.0680!
        # Distance from waypost (38.8951, -77.0315): ~3.17 km (> 2.05 km -> N5 gateways unchanged!).
        # Distance from dupont-circle (38.9096, -77.0434) to (38.8960, -77.0680): ~2.61 km (lo=4, hi=8 -> L6 4 cells passes!),
        # and displacement from dupont-circle is SOUTH-WEST (north = -1.51 km < 0), while connecticut-avenue travels NORTH (+y)!
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:woodley-park":
                h["anchor"] = {"lat": 38.8960, "lon": -77.0680}
        self._assert_fails_rule(mutated, "L5")

    def test_falsifying_L6_route_length_cells_per_km(self):
        # Connecticut Avenue is 2.29 km -> lo = max(2, ceil(2.86)) = 3, hi = 8.
        # Move woodley-park 3 cells south to [-8, 7]? Wait: rock-creek-trail-1 is at [-12, 7] [5, 1] -> overlaps [-8, 7].
        # Instead, move woodley-park 5 cells NORTH from [-8, 10] to [-8, 15], extend connecticut-avenue to [1, 9] (9 > hi=8),
        # and extend rock-creek-trail-2 from [1, 2] to [1, 7] (total 5+7=12 > 8)!
        # L1 (no overlap), L2 (only chain touches), L3 ([1, 9] has n>=1), L7, L4 (exact shared edges), L5 (still north) all pass -> fails L6!
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:woodley-park":
                h["at"] = [-8, 15]
        for r in mutated["cities"][0]["routes"]:
            if r["id"] == "route:washington-dc:connecticut-avenue":
                r["legs"][0]["cells"] = [1, 9]
            elif r["id"] == "route:washington-dc:rock-creek-trail":
                r["legs"][1]["cells"] = [1, 7]
        self._assert_fails_rule(mutated, "L6")

    def test_falsifying_L7_border_pair_bijection(self):
        # Removing one route while keeping its border pair in `borders` violates L7 (while L1-L3 still hold).
        mutated = copy.deepcopy(self.routes_data)
        mutated["cities"][0]["routes"] = [
            r for r in mutated["cities"][0]["routes"] if r["id"] != "route:washington-dc:q-street"
        ]
        self._assert_fails_rule(mutated, "L7")

    def test_falsifying_L8_blocks_and_legs_inside_city_pack(self):
        # Rigidly shift every neighbourhood and leg `at` by (+200, +200): L1-L7 all stay valid, while cells leave DC in the pack.
        mutated = copy.deepcopy(self.routes_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            h["at"] = [h["at"][0] + 200, h["at"][1] + 200]
        for r in mutated["cities"][0]["routes"]:
            for leg in r["legs"]:
                leg["at"] = [leg["at"][0] + 200, leg["at"][1] + 200]
        self._assert_fails_rule(mutated, "L8")


if __name__ == "__main__":
    unittest.main(verbosity=2)
