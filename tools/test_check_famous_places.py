#!/usr/bin/env python3
"""
tools/test_check_famous_places.py — Unit and falsification tests for famous_places.json validator.
Contract: docs/implementation_plan_famous_places.md §1 & docs/agent_execution_guide.md §7.1
"""

import copy
import json
import os
import sys
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from check_famous_places import validate_famous_places

class TestFamousPlacesValidation(unittest.TestCase):
    def setUp(self):
        self.config_path = os.path.join(REPO_ROOT, "game", "config", "famous_places.json")
        with open(self.config_path, "r", encoding="utf-8") as f:
            self.valid_data = json.load(f)

    def test_canonical_file_valid(self):
        """Assert canonical game/config/famous_places.json passes all validations."""
        self.assertTrue(validate_famous_places(self.config_path))

    def test_falsifying_duplicate_legendary(self):
        """Falsification test: Two places sharing the same legendary dex number must fail."""
        mutated = copy.deepcopy(self.valid_data)
        # Find two sites/spots and give them the same legendary_dex
        spots_and_sites = [p for p in mutated if p.get("legendary_dex") is not None]
        self.assertGreaterEqual(len(spots_and_sites), 2)
        spots_and_sites[1]["legendary_dex"] = spots_and_sites[0]["legendary_dex"]

        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
            json.dump(mutated, tf)
            tmp_name = tf.name

        try:
            with self.assertRaises(ValueError) as ctx:
                validate_famous_places(tmp_name)
            self.assertIn("Duplicate legendary dex", str(ctx.exception))
        finally:
            if os.path.exists(tmp_name):
                os.remove(tmp_name)

    def test_falsifying_interior_only_h(self):
        """Falsification test: An interior with only purpose 'H' (lacking T, W, L, or Q) must fail."""
        mutated = copy.deepcopy(self.valid_data)
        # Find first city with interiors and set an interior's purpose to 'H'
        for p in mutated:
            if p.get("kind") == "city" and p.get("interiors"):
                p["interiors"][0]["purposes"] = "H"
                break

        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
            json.dump(mutated, tf)
            tmp_name = tf.name

        try:
            with self.assertRaises(ValueError) as ctx:
                validate_famous_places(tmp_name)
            self.assertTrue(
                "< 2 purposes" in str(ctx.exception) or "lacks key purpose" in str(ctx.exception),
                f"Unexpected error: {ctx.exception}"
            )
        finally:
            if os.path.exists(tmp_name):
                os.remove(tmp_name)

if __name__ == "__main__":
    unittest.main()
