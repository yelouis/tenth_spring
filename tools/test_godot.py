#!/usr/bin/env python3
"""Unit tests for tools/godot.py launcher guardrails (Item 23 / F57, Item 92 / F115)."""

from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import godot as godot_launcher  # noqa: E402


class GodotLauncherTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self._tmp.name)
        self.scenetree_script = self.tmp_dir / "ok_tree.gd"
        self.scenetree_script.write_text(
            "extends SceneTree\nfunc _init() -> void:\n\tquit(0)\n",
            encoding="utf-8",
        )
        self.node_script = self.tmp_dir / "bad_node.gd"
        self.node_script.write_text(
            "extends Node\nfunc run_test() -> bool:\n\treturn true\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_refuses_script_flags_after_double_dash_without_spawning(self) -> None:
        expected_msg = (
            "godot.py: refusing --script after --: Godot would open the game on the real save. Put --script before --."
        )
        cases = [
            ["--", "--script", str(self.scenetree_script)],
            ["--", "-s", str(self.scenetree_script)],
            ["--", f"--script={self.scenetree_script}"],
            ["--memguard-step", "godot_tests", "--", "--extra", "--script", str(self.scenetree_script)],
        ]
        for argv in cases:
            with self.subTest(argv=argv):
                err_buf = io.StringIO()
                out_buf = io.StringIO()
                with mock.patch.dict(os.environ, {godot_launcher.BIN_ENV_KEY: sys.executable}), \
                     mock.patch.object(godot_launcher.subprocess, "run") as mock_run, \
                     redirect_stdout(out_buf), redirect_stderr(err_buf):
                    rc = godot_launcher.main(argv)
                self.assertEqual(rc, 2)
                self.assertIn(expected_msg, err_buf.getvalue())
                mock_run.assert_not_called()

    def test_allows_scenetree_script_before_double_dash(self) -> None:
        out_buf = io.StringIO()
        err_buf = io.StringIO()
        with mock.patch.dict(os.environ, {godot_launcher.BIN_ENV_KEY: sys.executable}), \
             mock.patch.object(
                 godot_launcher.subprocess,
                 "run",
                 return_value=mock.Mock(returncode=0),
             ) as mock_run, \
             redirect_stdout(out_buf), redirect_stderr(err_buf):
            rc = godot_launcher.main(["--script", str(self.scenetree_script), "--", "--custom-arg=1"])
        self.assertEqual(rc, 0)
        mock_run.assert_called_once()
        spawned_cmd = mock_run.call_args[0][0]
        self.assertLess(spawned_cmd.index("--script"), spawned_cmd.index("--"))
        self.assertIn("--custom-arg=1", spawned_cmd)

    def test_still_refuses_non_scenetree_script_before_double_dash(self) -> None:
        out_buf = io.StringIO()
        err_buf = io.StringIO()
        with mock.patch.dict(os.environ, {godot_launcher.BIN_ENV_KEY: sys.executable}), \
             mock.patch.object(godot_launcher.subprocess, "run") as mock_run, \
             redirect_stdout(out_buf), redirect_stderr(err_buf):
            rc = godot_launcher.main(["--script", str(self.node_script)])
        self.assertEqual(rc, 2)
        self.assertIn("doesn't extend SceneTree or MainLoop", err_buf.getvalue())
        mock_run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
