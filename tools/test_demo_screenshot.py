#!/usr/bin/env python3
"""
tools/test_demo_screenshot.py — Regression tests for tools/demo_screenshot.py wrapper.
Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6
"""

import os
import subprocess
import sys
import unittest

class TestDemoScreenshotWrapper(unittest.TestCase):
    def setUp(self):
        self.repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.wrapper_path = os.path.join(self.repo_root, "tools", "demo_screenshot.py")

    def test_refuse_in_repo_relative_path(self):
        """Assert wrapper refuses in-repo relative path with exit code 2."""
        res = subprocess.run(
            [sys.executable, "-I", self.wrapper_path, "--out-dir", "game"],
            cwd=self.repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        self.assertEqual(res.returncode, 2, f"Expected exit code 2, got {res.returncode}")
        self.assertIn("must be outside the repository", res.stderr)

    def test_refuse_in_repo_absolute_path(self):
        """Assert wrapper refuses in-repo absolute path with exit code 2."""
        in_repo_abs = os.path.join(self.repo_root, "screens")
        res = subprocess.run(
            [sys.executable, "-I", self.wrapper_path, "--out-dir", in_repo_abs],
            cwd=self.repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        self.assertEqual(res.returncode, 2, f"Expected exit code 2, got {res.returncode}")
        self.assertIn("must be outside the repository", res.stderr)

    def test_help_exits_zero(self):
        """Assert --help prints usage and exits 0."""
        res = subprocess.run(
            [sys.executable, "-I", self.wrapper_path, "--help"],
            cwd=self.repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("--out-dir", res.stdout)
        self.assertIn("--demo-dir", res.stdout)
        self.assertIn("--focus", res.stdout)
        self.assertIn("--filename", res.stdout)

if __name__ == "__main__":
    unittest.main()
