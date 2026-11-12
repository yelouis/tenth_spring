#!/usr/bin/env python3
"""
tools/test_check_neighbourhoods.py — Unit and 14-rule falsification suite for check_neighbourhoods.py (Item 47)
Contract: docs/implementation_plan_dc_trial.md §1.4 & §9, docs/agent_execution_guide.md §3
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


class TestCheckNeighbourhoods(unittest.TestCase):
    def setUp(self):
        with open(CANONICAL_CONFIG, "r", encoding="utf-8") as f:
            self.valid_data = json.load(f)

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
            "[CHECK NEIGHBOURHOODS OK] 1 cities, 8 neighbourhoods, 1 camps.",
        )

    def test_falsifying_N1_version_and_city_entry(self):
        mutated = copy.deepcopy(self.valid_data)
        mutated["version"] = 2
        self._assert_fails_rule(mutated, "N1")

    def test_falsifying_N2_neighbourhood_count(self):
        mutated = copy.deepcopy(self.valid_data)
        mutated["cities"][0]["neighbourhoods"].pop()
        self._assert_fails_rule(mutated, "N2")

    def test_falsifying_N3_id_format_and_uniqueness(self):
        mutated = copy.deepcopy(self.valid_data)
        mutated["cities"][0]["neighbourhoods"][0]["id"] = "hood:washington-dc:National_Mall"
        self._assert_fails_rule(mutated, "N3")

    def test_falsifying_N4_role_counts(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:union-station":
                h["role"] = "gateway"
        self._assert_fails_rule(mutated, "N4")

    def test_falsifying_N5_gateways_nearest_waypost(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:capitol-hill":
                h["role"] = "inner"
            elif h["id"] == "hood:washington-dc:union-station":
                h["role"] = "gateway"
        self._assert_fails_rule(mutated, "N5")

    def test_falsifying_N6_block_cell_dimensions(self):
        mutated = copy.deepcopy(self.valid_data)
        mutated["cities"][0]["neighbourhoods"][2]["cells"] = [4, 2]
        self._assert_fails_rule(mutated, "N6")

    def test_falsifying_N7_cells_inside_city_pack(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:woodley-park":
                h["anchor"] = {"lat": 39.20, "lon": -77.05}
        self._assert_fails_rule(mutated, "N7")

    def test_falsifying_N8_minimum_block_gap(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:union-station":
                h["anchor"] = {"lat": 38.893529, "lon": -77.006173}
        self._assert_fails_rule(mutated, "N8")

    def test_falsifying_N9_borders_symmetric_and_reachable(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:woodley-park":
                h["borders"] = []
            else:
                h["borders"] = [
                    b for b in h["borders"] if b != "hood:washington-dc:woodley-park"
                ]
        self._assert_fails_rule(mutated, "N9")

    def test_falsifying_N10_zone_haunt_and_ruin_level(self):
        mutated = copy.deepcopy(self.valid_data)
        mutated["cities"][0]["neighbourhoods"][2]["zone"] = "suburb"
        self._assert_fails_rule(mutated, "N10")

    def test_falsifying_N11_landmarks_schema(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:tidal-basin":
                h["landmarks"] = [h["landmarks"][0]]
        self._assert_fails_rule(mutated, "N11")

    def test_falsifying_N12_city_interiors_bijection(self):
        mutated = copy.deepcopy(self.valid_data)
        del mutated["cities"][0]["neighbourhoods"][0]["landmarks"][0]["interior"]
        self._assert_fails_rule(mutated, "N12")

    def test_falsifying_N13_main_quest_schema(self):
        mutated = copy.deepcopy(self.valid_data)
        for h in mutated["cities"][0]["neighbourhoods"]:
            if h["id"] == "hood:washington-dc:dupont-circle":
                h["main_quest"]["pattern"] = "time_of_day"
        self._assert_fails_rule(mutated, "N13")

    def test_falsifying_N14_ready_flag_and_maps_present(self):
        mutated = copy.deepcopy(self.valid_data)
        mutated["cities"][0]["ready"] = True
        mutated["cities"][0]["camp"]["map"] = "washington-dc/missing-falsifier.json"
        self._assert_fails_rule(mutated, "N14")


if __name__ == "__main__":
    unittest.main(verbosity=2)
