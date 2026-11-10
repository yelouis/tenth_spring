#!/usr/bin/env python3
"""Unit and falsifying tests for tools/rom_spike/data_pack_spike.py (Item 29)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.rom_spike import data_pack_spike as dps  # noqa: E402


class DataPackSpikeTests(unittest.TestCase):
    def test_validate_fan_sprite_id_refuses_rom_range_and_out_of_scope(self) -> None:
        for bad_id in (0, 1, 25, 94, 487, 609, 649, 906, 1005, 10032, 10091):
            with self.subTest(bad_id=bad_id):
                with self.assertRaises(ValueError):
                    dps.validate_fan_sprite_id(bad_id)

        for good_id in (650, 700, 778, 887, 899, 905, 10033, 10038, 10090):
            dps.validate_fan_sprite_id(good_id)

    def test_committed_manifests_and_credits_schema_and_no_rom_ids(self) -> None:
        for p in (
            dps.DATA_SOURCES_PATH,
            dps.DATA_PACK_MANIFEST_PATH,
            dps.FAN_SPRITE_MANIFEST_PATH,
            dps.FAN_SPRITE_CREDITS_PATH,
        ):
            self.assertTrue(p.is_file(), f"Missing committed config file: {p}")

        dp_man = json.loads(dps.DATA_PACK_MANIFEST_PATH.read_text(encoding="utf-8"))
        self.assertEqual(len(dp_man["files"]), len(dps.CSV_FILES))
        for fname, meta in dp_man["files"].items():
            self.assertGreater(meta["size"], 0, fname)
            self.assertEqual(len(meta["sha256"]), 64, fname)

        fs_man = json.loads(dps.FAN_SPRITE_MANIFEST_PATH.read_text(encoding="utf-8"))
        self.assertEqual(fs_man["species_range"], [650, 905])
        self.assertEqual(len(fs_man["mega_pokemon_ids"]), 48)
        self.assertEqual(fs_man["pending_species_dex"], [])
        self.assertEqual(fs_man["pending_mega_pokemon_ids"], [])
        self.assertEqual(fs_man["total_files"], 304 * 4)
        for vname in ("front", "back", "shiny", "back_shiny"):
            vmap = fs_man["files"][vname]
            self.assertEqual(len(vmap), 304)
            for k_str, meta in vmap.items():
                sid = int(k_str)
                self.assertGreaterEqual(sid, 650, f"Found #1-649 sprite id {sid} in {vname}")
                self.assertGreater(meta["size"], 100)
                self.assertEqual(len(meta["sha256"]), 64)

        credits_doc = json.loads(dps.FAN_SPRITE_CREDITS_PATH.read_text(encoding="utf-8"))
        self.assertEqual(len(credits_doc["species_credits"]), 256)
        self.assertEqual(len(credits_doc["mega_form_credits"]), 48)
        for d in range(650, 906):
            artists = credits_doc["species_credits"][str(d)]
            self.assertTrue(isinstance(artists, list) and len(artists) >= 1, f"Missing credit for #{d}")

    def test_falsifier_catches_species_name_leak_and_committed_files_have_zero(self) -> None:
        sample_names = ["Bulbasaur", "Charizard", "Gengar", "Espeon", "Vanillite", "Chandelure", "Mimikyu", "Dragapult", "Enamorus"]
        with tempfile.TemporaryDirectory() as tmp:
            leaky = Path(tmp) / "leaky.json"
            leaky.write_text('{"artist": "Espeon Scientist", "form": "gengar-mega"}\n', encoding="utf-8")
            leaks = dps.verify_no_species_names_in_files([leaky], sample_names)
            leaked_species = {s for _, s in leaks}
            self.assertIn("Espeon", leaked_species)
            self.assertIn("Gengar", leaked_species)

        committed = [
            dps.DATA_SOURCES_PATH,
            dps.DATA_PACK_MANIFEST_PATH,
            dps.FAN_SPRITE_MANIFEST_PATH,
            dps.FAN_SPRITE_CREDITS_PATH,
        ]
        self.assertEqual(dps.verify_no_species_names_in_files(committed, sample_names), [])

    def test_spike_idempotency_and_full_species_grep_when_cache_present(self) -> None:
        spike_dir = Path(os.environ.get("TENTH_SPRING_DATA_PACK", str(dps.DEFAULT_OUT_DIR)))
        if not (spike_dir / "csv" / "pokemon_species_names.csv").is_file():
            self.skipTest(f"Data spike cache not present at {spike_dir}")

        before_dp = dps.DATA_PACK_MANIFEST_PATH.read_bytes()
        before_fs = dps.FAN_SPRITE_MANIFEST_PATH.read_bytes()
        before_cr = dps.FAN_SPRITE_CREDITS_PATH.read_bytes()

        report = dps.run_spike(spike_dir)
        self.assertEqual(report["species_count"], 905)
        self.assertEqual(report["mega_form_count"], 48)
        self.assertEqual(report["moves"]["kept_move_count"], 778)
        self.assertEqual(report["species_name_leaks_in_committed_configs"], 0)

        self.assertEqual(dps.DATA_PACK_MANIFEST_PATH.read_bytes(), before_dp)
        self.assertEqual(dps.FAN_SPRITE_MANIFEST_PATH.read_bytes(), before_fs)
        self.assertEqual(dps.FAN_SPRITE_CREDITS_PATH.read_bytes(), before_cr)


if __name__ == "__main__":
    unittest.main()
