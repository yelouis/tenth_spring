#!/usr/bin/env python3
"""
Unit and regression tests for Developer Tooling Memory Guard (tools/memguard.py).
Contract: docs/design_memory_and_resources.md §4

Tests the 7 required cases:
1. admits when there is room;
2. waits, then admits when memory frees up;
3. times out with exit 75 and the exact message;
4. a real sleep child is stopped when fake pressure turns critical twice (exit 76);
5. falsifying, real memory: a child that allocates ~200 MiB under a 50 MiB budget is stopped as a runaway;
6. a second process waits for the lock, and the lock frees when its holder is SIGKILLed;
7. a nested run with TENTH_SPRING_MEMGUARD_HELD set doesn't deadlock.
"""

import fcntl
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEMGUARD_PATH = os.path.join(REPO_ROOT, "tools", "memguard.py")

sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
import memguard


class TestMemguard(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="memguard_test_")
        self.lock_dir = os.path.join(self.test_dir, "locks")
        os.makedirs(self.lock_dir, exist_ok=True)
        self.orig_lock_env = os.environ.get("TENTH_SPRING_LOCK_DIR")
        self.orig_held_env = os.environ.get("TENTH_SPRING_MEMGUARD_HELD")
        os.environ["TENTH_SPRING_LOCK_DIR"] = self.lock_dir
        if "TENTH_SPRING_MEMGUARD_HELD" in os.environ:
            del os.environ["TENTH_SPRING_MEMGUARD_HELD"]
        memguard.reset_injections()

    def tearDown(self):
        memguard.reset_injections()
        if self.orig_lock_env is not None:
            os.environ["TENTH_SPRING_LOCK_DIR"] = self.orig_lock_env
        else:
            os.environ.pop("TENTH_SPRING_LOCK_DIR", None)
        if self.orig_held_env is not None:
            os.environ["TENTH_SPRING_MEMGUARD_HELD"] = self.orig_held_env
        else:
            os.environ.pop("TENTH_SPRING_MEMGUARD_HELD", None)
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_case_1_admits_when_room(self):
        """Case 1: Admits when there is room."""
        # 20 GiB available, 64 GiB total, normal pressure
        memguard.set_memory_reader(
            lambda: memguard.MemoryInfo(
                available_bytes=20 * (1024**3),
                total_bytes=64 * (1024**3),
                pressure_level=1
            )
        )
        cmd = [sys.executable, "-c", "import sys; sys.exit(0)"]
        code = memguard.run_guarded("test_c1", cmd, override_budget_gib=1.0)
        self.assertEqual(code, 0)

        # Check log
        log_file = memguard.get_log_file()
        self.assertTrue(os.path.isfile(log_file))
        with open(log_file, "r", encoding="utf-8") as f:
            lines = [json.loads(l) for l in f if l.strip()]
        self.assertTrue(any(rec["step"] == "test_c1" and rec["outcome"] == "ok" for rec in lines))

    def test_case_2_waits_then_admits(self):
        """Case 2: Waits, then admits when memory frees up."""
        call_count = [0]

        def memory_sequence():
            call_count[0] += 1
            if call_count[0] <= 1:
                # Initially insufficient (1 GiB available, need 1 GiB budget + 6.4 GiB floor)
                return memguard.MemoryInfo(
                    available_bytes=1 * (1024**3),
                    total_bytes=64 * (1024**3),
                    pressure_level=1
                )
            # Then sufficient
            return memguard.MemoryInfo(
                available_bytes=20 * (1024**3),
                total_bytes=64 * (1024**3),
                pressure_level=1
            )

        memguard.set_memory_reader(memory_sequence)
        cmd = [sys.executable, "-c", "import sys; sys.exit(0)"]
        code = memguard.run_guarded("test_c2", cmd, override_budget_gib=1.0, poll_seconds=0.05)
        self.assertEqual(code, 0)
        self.assertGreaterEqual(call_count[0], 2)

        # Check log waited_ms
        log_file = memguard.get_log_file()
        with open(log_file, "r", encoding="utf-8") as f:
            records = [json.loads(l) for l in f if l.strip()]
        c2_records = [r for r in records if r["step"] == "test_c2"]
        self.assertTrue(c2_records)
        self.assertGreater(c2_records[-1]["waited_ms"], 0)

    def test_case_3_times_out_with_exit_75(self):
        """Case 3: Times out with exit 75 and exact message."""
        # Always insufficient memory
        memguard.set_memory_reader(
            lambda: memguard.MemoryInfo(
                available_bytes=1 * (1024**3),
                total_bytes=64 * (1024**3),
                pressure_level=1
            )
        )
        cmd = [sys.executable, "-c", "import sys; sys.exit(0)"]

        with self.assertRaises(SystemExit) as cm:
            memguard.run_guarded(
                "test_c3",
                cmd,
                override_budget_gib=2.0,
                admit_timeout=0.1,
                poll_seconds=0.05
            )
        self.assertEqual(cm.exception.code, 75)

        # Verify exit code and exact message format via subprocess
        env = os.environ.copy()
        env["TENTH_SPRING_LOCK_DIR"] = self.lock_dir
        tools_dir = os.path.join(REPO_ROOT, "tools")
        sub = subprocess.run(
            [
                sys.executable,
                "-I",
                "-c",
                f"import sys; sys.path.insert(0, '{tools_dir}'); import memguard; "
                f"memguard.set_memory_reader(lambda: memguard.MemoryInfo(available_bytes=1073741824, total_bytes=68719476736, pressure_level=1)); "
                f"memguard.run_guarded('test_step_timeout', [sys.executable, '-c', 'sys.exit(0)'], override_budget_gib=2.0, admit_timeout=0.1, poll_seconds=0.05)"
            ],
            capture_output=True,
            text=True,
            env=env
        )
        self.assertEqual(sub.returncode, 75)
        # Expected: need 8.4 GiB (2.0 budget + 6.4 floor), have 1.0 GiB
        expected_msg = (
            "memguard: not enough free memory for test_step_timeout (need 8.4 GiB, have 1.0 GiB) — "
            "other programs are using it; close some or try later"
        )
        self.assertIn(expected_msg, sub.stderr)

    def test_case_4_stops_on_critical_pressure_twice(self):
        """Case 4: Real sleep child is stopped when fake pressure turns critical twice (exit 76)."""
        calls = [0]

        def fake_reader():
            calls[0] += 1
            # Normal pressure during admission check, then critical pressure (4) while running
            p = 1 if calls[0] <= 1 else 4
            return memguard.MemoryInfo(
                available_bytes=20 * (1024**3),
                total_bytes=64 * (1024**3),
                pressure_level=p
            )

        memguard.set_memory_reader(fake_reader)
        cmd = [sys.executable, "-c", "import time; time.sleep(10)"]

        with self.assertRaises(SystemExit) as cm:
            memguard.run_guarded(
                "test_c4",
                cmd,
                override_budget_gib=1.0,
                poll_seconds=0.05,
                stop_grace=1.0
            )
        self.assertEqual(cm.exception.code, 76)

        log_file = memguard.get_log_file()
        with open(log_file, "r", encoding="utf-8") as f:
            records = [json.loads(l) for l in f if l.strip()]
        c4_records = [r for r in records if r["step"] == "test_c4"]
        self.assertTrue(c4_records)
        self.assertEqual(c4_records[-1]["outcome"], "stopped:critical memory pressure")

    def test_case_5_falsifying_runaway_memory(self):
        """Case 5: Falsifying, real memory: child allocating ~200 MiB under 50 MiB budget stopped as runaway."""
        # 50 MiB budget (~0.0488 GiB); cap is 50 * 1.5 = 75 MiB
        budget_gib = 50.0 / 1024.0

        # Child allocates 200 MiB in 20 MiB steps
        child_code = (
            "import time; "
            "chunks = []; "
            "[chunks.append(bytearray(20 * 1024 * 1024)) or time.sleep(0.05) for _ in range(10)]"
        )
        cmd = [sys.executable, "-c", child_code]

        # First run: with runaway check enabled, must exit 76
        with self.assertRaises(SystemExit) as cm:
            memguard.run_guarded(
                "test_c5_runaway",
                cmd,
                override_budget_gib=budget_gib,
                poll_seconds=0.05,
                stop_grace=1.0,
                allow_rss_check=True
            )
        self.assertEqual(cm.exception.code, 76)

        log_file = memguard.get_log_file()
        with open(log_file, "r", encoding="utf-8") as f:
            records = [json.loads(l) for l in f if l.strip()]
        c5_records = [r for r in records if r["step"] == "test_c5_runaway"]
        self.assertTrue(c5_records)
        self.assertEqual(c5_records[-1]["outcome"], "stopped:tree RSS exceeded budget")

        # Falsification check: if RSS check is disabled, the same run completes with exit 0
        code = memguard.run_guarded(
            "test_c5_no_check",
            cmd,
            override_budget_gib=budget_gib,
            poll_seconds=0.05,
            stop_grace=1.0,
            allow_rss_check=False
        )
        self.assertEqual(code, 0)

    def test_case_6_lock_serialization_and_release_on_sigkill(self):
        """Case 6: Second process waits for lock, and lock frees when holder is SIGKILLed."""
        lock_file = memguard.get_lock_file()

        # Process A holds the flock and sleeps
        proc_a_script = (
            f"import fcntl, time; "
            f"f = open('{lock_file}', 'a+'); "
            f"fcntl.flock(f.fileno(), fcntl.LOCK_EX); "
            f"print('LOCKED', flush=True); "
            f"time.sleep(30)"
        )
        proc_a = subprocess.Popen(
            [sys.executable, "-c", proc_a_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Wait until Proc A holds lock
        line = proc_a.stdout.readline().strip()
        self.assertEqual(line, "LOCKED")

        # Process B starts memguard run trying to acquire lock
        env = os.environ.copy()
        env["TENTH_SPRING_LOCK_DIR"] = self.lock_dir
        proc_b = subprocess.Popen(
            [
                sys.executable,
                "-I",
                MEMGUARD_PATH,
                "run",
                "test_c6_waiter",
                "--",
                sys.executable,
                "-c",
                "import sys; sys.exit(0)"
            ],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Allow Process B to enter lock wait
        time.sleep(0.5)
        self.assertIsNone(proc_b.poll())

        # SIGKILL Process A
        proc_a.kill()
        proc_a.communicate()

        # Process B should now acquire lock and exit 0
        proc_b.communicate(timeout=5.0)
        self.assertEqual(proc_b.returncode, 0)

    def test_case_7_nested_run_does_not_deadlock(self):
        """Case 7: Nested run with TENTH_SPRING_MEMGUARD_HELD set doesn't deadlock."""
        env = os.environ.copy()
        env["TENTH_SPRING_LOCK_DIR"] = self.lock_dir
        env["TENTH_SPRING_MEMGUARD_HELD"] = "outer_step"

        res = subprocess.run(
            [
                sys.executable,
                "-I",
                MEMGUARD_PATH,
                "run",
                "inner_step",
                "--",
                sys.executable,
                "-c",
                "import sys; print('nested ok'); sys.exit(0)"
            ],
            capture_output=True,
            text=True,
            env=env,
            timeout=5.0
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("nested ok", res.stdout)


if __name__ == "__main__":
    unittest.main()
