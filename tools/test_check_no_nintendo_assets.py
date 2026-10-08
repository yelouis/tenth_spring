#!/usr/bin/env python3
"""
Unit and regression tests for Public-Repo IP Guard (check_no_nintendo_assets.py).

Asserts exit codes and detection accuracy across all seven core and bypass cases
using throwaway git repositories.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

GUARD_SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), "check_no_nintendo_assets.py"))

class TestCheckNoNintendoAssets(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="ip_guard_test_")
        self._run_git(["init"])
        self._run_git(["config", "user.email", "test@example.com"])
        self._run_git(["config", "user.name", "Test Runner"])
        # Initial commit so HEAD exists
        init_file = os.path.join(self.test_dir, "init.txt")
        with open(init_file, "w", encoding="utf-8") as f:
            f.write("initial clean commit\n")
        self._run_git(["add", "init.txt"])
        self._run_git(["commit", "-m", "init"])

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _run_git(self, args):
        return subprocess.run(
            ["git"] + args,
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )

    def _run_guard(self, args=None):
        cmd = [sys.executable, "-I", GUARD_SCRIPT]
        if args:
            cmd.extend(args)
        return subprocess.run(
            cmd,
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

    def test_staged_narc_magic(self):
        """1. Staged x.bin starting with NARC magic header must fail (exit 1)."""
        file_path = os.path.join(self.test_dir, "x.bin")
        with open(file_path, "wb") as f:
            f.write(b"NARC" + b"\x00" * 12)
        self._run_git(["add", "x.bin"])

        res = self._run_guard(["--staged"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("x.bin", res.stdout)
        self.assertIn("NARC magic header", res.stdout)

    def test_staged_cpue_game_code(self):
        """2. Staged file with CPUE at 0x0C must fail (exit 1)."""
        file_path = os.path.join(self.test_dir, "game.bin")
        with open(file_path, "wb") as f:
            f.write(b"\x00" * 12 + b"CPUE")
        self._run_git(["add", "game.bin"])

        res = self._run_guard(["--staged"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("game.bin", res.stdout)
        self.assertIn("CPUE", res.stdout)

    def test_staged_empty_nds(self):
        """3. Staged empty test.nds must fail (exit 1)."""
        file_path = os.path.join(self.test_dir, "test.nds")
        with open(file_path, "wb") as f:
            pass
        self._run_git(["add", "test.nds"])

        res = self._run_guard(["--staged"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("test.nds", res.stdout)
        self.assertIn(".nds", res.stdout)

    def test_clean_repo(self):
        """4. Clean repository must pass (exit 0)."""
        clean_file = os.path.join(self.test_dir, "clean.py")
        with open(clean_file, "w", encoding="utf-8") as f:
            f.write("print('hello')\n")
        self._run_git(["add", "clean.py"])
        self._run_git(["commit", "-m", "add clean file"])

        res_default = self._run_guard()
        self.assertEqual(res_default.returncode, 0)

        res_staged = self._run_guard(["--staged"])
        self.assertEqual(res_staged.returncode, 0)

    def test_git_mv_rename(self):
        """5. git mv ok.txt rom.nds must fail in staged mode (exit 1)."""
        ok_file = os.path.join(self.test_dir, "ok.txt")
        with open(ok_file, "w", encoding="utf-8") as f:
            f.write("sample ok text\n")
        self._run_git(["add", "ok.txt"])
        self._run_git(["commit", "-m", "add ok.txt"])

        self._run_git(["mv", "ok.txt", "rom.nds"])

        res = self._run_guard(["--staged"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("rom.nds", res.stdout)

    def test_staged_cpue_blob_disk_overwritten(self):
        """6. Staged CPUE blob must be caught even if disk copy is modified to safe text (exit 1)."""
        bad_file = os.path.join(self.test_dir, "target.bin")
        with open(bad_file, "wb") as f:
            f.write(b"\x00" * 12 + b"CPUE")
        self._run_git(["add", "target.bin"])

        # Overwrite disk copy with benign data without git add
        with open(bad_file, "wb") as f:
            f.write(b"completely benign text on disk")

        res = self._run_guard(["--staged"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("target.bin", res.stdout)
        self.assertIn("CPUE", res.stdout)

    def test_range_add_then_delete_rom(self):
        """7. Commit range where ROM is added then deleted in subsequent commit must fail (exit 1)."""
        base_sha = self._run_git(["rev-parse", "HEAD"]).stdout.strip()

        # Commit adding ROM
        rom_file = os.path.join(self.test_dir, "rom.nds")
        with open(rom_file, "wb") as f:
            f.write(b"dummy rom bytes")
        self._run_git(["add", "rom.nds"])
        self._run_git(["commit", "-m", "accidental rom commit"])
        bad_sha = self._run_git(["rev-parse", "HEAD"]).stdout.strip()

        # Commit deleting ROM
        self._run_git(["rm", "rom.nds"])
        self._run_git(["commit", "-m", "deleted rom"])
        head_sha = self._run_git(["rev-parse", "HEAD"]).stdout.strip()

        res = self._run_guard(["--range", f"{base_sha}..{head_sha}"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("rom.nds", res.stdout)
        self.assertIn(bad_sha[:7], res.stdout)

    def test_range_merge_introducing_rom(self):
        """8. Merge commit introducing CPUE-headed file must fail in range mode (exit 1)."""
        base_sha = self._run_git(["rev-parse", "HEAD"]).stdout.strip()
        current_branch = self._run_git(["rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()

        # Create branch 'feature' with a bad file
        self._run_git(["checkout", "-b", "feature"])
        bad_file = os.path.join(self.test_dir, "bad.bin")
        with open(bad_file, "wb") as f:
            f.write(b"\x00" * 12 + b"CPUE")
        self._run_git(["add", "bad.bin"])
        self._run_git(["commit", "-m", "add bad file in feature"])

        # Switch back to initial branch and make a commit
        self._run_git(["checkout", current_branch])
        main_file = os.path.join(self.test_dir, "other.txt")
        with open(main_file, "w") as f:
            f.write("other change")
        self._run_git(["add", "other.txt"])
        self._run_git(["commit", "-m", "other change on main"])

        # Merge feature with --no-ff
        self._run_git(["merge", "--no-ff", "feature", "-m", "merge feature into main"])
        head_sha = self._run_git(["rev-parse", "HEAD"]).stdout.strip()

        res = self._run_guard(["--range", f"{base_sha}..{head_sha}"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("bad.bin", res.stdout)

    def test_range_unknown_sha(self):
        """9. Unknown SHA in commit range must fail (exit 1)."""
        res = self._run_guard(["--range", "0123456789abcdef0123456789abcdef01234567..HEAD"])
        self.assertEqual(res.returncode, 1)

    def test_staged_forbidden_prefixes(self):
        """10. CPUP, CPUJ, IRBO, and IRAO-headed blobs named x.bin must each exit 1."""
        for code in [b"CPUP", b"CPUJ", b"IRBO", b"IRAO"]:
            file_path = os.path.join(self.test_dir, "x.bin")
            with open(file_path, "wb") as f:
                f.write(b"\x00" * 12 + code)
            self._run_git(["add", "x.bin"])

            res = self._run_guard(["--staged"])
            self.assertEqual(res.returncode, 1, f"Expected code {code} to be rejected")
            self.assertIn("x.bin", res.stdout)

            self._run_git(["rm", "-f", "x.bin"])

    def test_staged_prefix_not_anything(self):
        """11. A 16-byte file with CPX at 0x0C must pass (exit 0), proving prefix is not 'anything'."""
        file_path = os.path.join(self.test_dir, "x.bin")
        with open(file_path, "wb") as f:
            f.write(b"\x00" * 12 + b"CPX\x00")
        self._run_git(["add", "x.bin"])

        res = self._run_guard(["--staged"])
        self.assertEqual(res.returncode, 0)
        self._run_git(["rm", "-f", "x.bin"])

if __name__ == "__main__":
    unittest.main()
