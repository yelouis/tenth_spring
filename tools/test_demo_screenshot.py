#!/usr/bin/env python3
"""
tools/test_demo_screenshot.py — Regression tests for tools/demo_screenshot.py wrapper.
Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6
"""

import contextlib
import io
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
        self.assertIn("--timeout", res.stdout)

    def test_timeout_is_forwarded_and_exit_3_is_passed_on(self):
        """Item 25b: --timeout reaches the game, and the game's exit code 3 (a stalled capture) ends the wrapper with 3."""
        import importlib.util
        import tempfile
        from unittest import mock

        spec = importlib.util.spec_from_file_location("demo_screenshot_under_test", self.wrapper_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        seen = []

        def fake_run(cmd, **kwargs):
            seen.append(cmd)
            return mock.Mock(returncode=3)

        with tempfile.TemporaryDirectory() as out_dir:
            argv = ["demo_screenshot.py", "--out-dir", out_dir, "--zoom", "0.0625", "--timeout", "7"]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.dict(os.environ, {"TENTH_SPRING_MEMGUARD_HELD": "1"}), \
                    mock.patch.object(module.subprocess, "run", fake_run):
                with self.assertRaises(SystemExit) as raised, \
                        contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    module.main()
        self.assertEqual(raised.exception.code, 3)
        self.assertEqual(len(seen), 1)
        self.assertIn("--timeout=7", seen[0])

    def test_timeout_is_not_forwarded_when_not_given(self):
        """Without --timeout the game's own default (120 s) applies."""
        import importlib.util
        import tempfile
        from unittest import mock

        spec = importlib.util.spec_from_file_location("demo_screenshot_under_test", self.wrapper_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        seen = []

        def fake_run(cmd, **kwargs):
            seen.append(cmd)
            return mock.Mock(returncode=3)

        with tempfile.TemporaryDirectory() as out_dir:
            argv = ["demo_screenshot.py", "--out-dir", out_dir]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.dict(os.environ, {"TENTH_SPRING_MEMGUARD_HELD": "1"}), \
                    mock.patch.object(module.subprocess, "run", fake_run):
                with self.assertRaises(SystemExit), \
                        contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    module.main()
        self.assertFalse(any(a.startswith("--timeout") for a in seen[0]))

if __name__ == "__main__":
    unittest.main()
