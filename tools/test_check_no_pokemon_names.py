#!/usr/bin/env python3
"""
tools/test_check_no_pokemon_names.py — Unit tests for tools/check_no_pokemon_names.py (Item 89 / F113).
Uses strictly synthetic names in temporary fixtures (zero Nintendo names).
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest


class TestCheckNoPokemonNames(unittest.TestCase):
    def setUp(self):
        self.repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.script = os.path.join(self.repo_root, "tools", "check_no_pokemon_names.py")

    def _init_temp_repo(self, root):
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=root, check=True)

    def _write_synthetic_cache(self, cache_dir):
        en_dir = os.path.join(cache_dir, "text", "en")
        os.makedirs(en_dir, exist_ok=True)
        with open(os.path.join(en_dir, "species.json"), "w", encoding="utf-8") as fh:
            json.dump({"1": "Zorbax", "2": "Rugcat"}, fh)
        with open(os.path.join(en_dir, "moves.json"), "w", encoding="utf-8") as fh:
            json.dump({"10": "Void Slash", "11": "Protect"}, fh)
        with open(os.path.join(en_dir, "abilities.json"), "w", encoding="utf-8") as fh:
            json.dump({"20": "Mist Veil", "21": "Sturdy"}, fh)
        with open(os.path.join(en_dir, "items.json"), "w", encoding="utf-8") as fh:
            json.dump({"30": "Star Elixir", "31": "Potion"}, fh)

    def _run_guard(self, repo_dir, cache_dir, allow_path, extra_args=None):
        cmd = [
            sys.executable, "-I", self.script,
            "--repo-root", repo_dir,
            "--cache-dir", cache_dir,
            "--allowlist", allow_path,
        ]
        if extra_args:
            cmd.extend(extra_args)
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_missing_cache_skips_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "repo")
            os.makedirs(repo)
            self._init_temp_repo(repo)
            allow = os.path.join(tmp, "allow.txt")
            with open(allow, "w", encoding="utf-8") as fh:
                fh.write("# empty\n")
            res = self._run_guard(repo, os.path.join(tmp, "no_such_cache"), allow)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertIn("[NAME GUARD SKIPPED] no data cache", res.stdout)

    def test_staged_species_and_special_move_item_trigger_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "repo")
            cache = os.path.join(tmp, "cache")
            os.makedirs(os.path.join(repo, "game"))
            self._init_temp_repo(repo)
            self._write_synthetic_cache(cache)
            allow = os.path.join(tmp, "allow.txt")
            with open(allow, "w", encoding="utf-8") as fh:
                fh.write("Rugcat carpet\n")

            bad = os.path.join(repo, "game", "sample.gd")
            with open(bad, "w", encoding="utf-8") as fh:
                fh.write("# Zorbax uses Void Slash with Mist Veil and Star Elixir\n")
            subprocess.run(["git", "add", "game/sample.gd"], cwd=repo, check=True)

            res = self._run_guard(repo, cache, allow, ["--staged"])
            self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
            self.assertIn("[NAME GUARD FAIL] game/sample.gd:1 (species #1)", res.stdout)
            self.assertIn("[NAME GUARD FAIL] game/sample.gd:1 (move #10)", res.stdout)
            self.assertIn("[NAME GUARD FAIL] game/sample.gd:1 (ability #20)", res.stdout)
            self.assertIn("[NAME GUARD FAIL] game/sample.gd:1 (item #30)", res.stdout)

    def test_allowlist_and_single_word_moves_and_docs_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "repo")
            cache = os.path.join(tmp, "cache")
            os.makedirs(os.path.join(repo, "game"))
            os.makedirs(os.path.join(repo, "docs"))
            self._init_temp_repo(repo)
            self._write_synthetic_cache(cache)
            allow = os.path.join(tmp, "allow.txt")
            with open(allow, "w", encoding="utf-8") as fh:
                fh.write("Rugcat carpet\n")

            ok_file = os.path.join(repo, "game", "ok.gd")
            with open(ok_file, "w", encoding="utf-8") as fh:
                fh.write('# A Rugcat carpet; ordinary words Protect, Sturdy, Potion; lowercase zorbax\n')
            doc_file = os.path.join(repo, "docs", "notes.md")
            with open(doc_file, "w", encoding="utf-8") as fh:
                fh.write("Zorbax is fine inside local docs/\n")
            subprocess.run(["git", "add", "game/ok.gd", "docs/notes.md"], cwd=repo, check=True)

            res = self._run_guard(repo, cache, allow, ["--staged"])
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertIn("[NAME GUARD OK] scanned 1 files", res.stdout)

            # Bare non-allowlisted species name must still fail
            with open(ok_file, "w", encoding="utf-8") as fh:
                fh.write('# Bare Rugcat without carpet\n')
            subprocess.run(["git", "add", "game/ok.gd"], cwd=repo, check=True)
            res2 = self._run_guard(repo, cache, allow, ["--staged"])
            self.assertEqual(res2.returncode, 1, res2.stdout + res2.stderr)
            self.assertIn("[NAME GUARD FAIL] game/ok.gd:1 (species #2)", res2.stdout)


if __name__ == "__main__":
    unittest.main()
