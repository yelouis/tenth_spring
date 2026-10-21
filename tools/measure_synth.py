#!/usr/bin/env python3
"""
tools/measure_synth.py — Standalone tool to measure synthesis statistics on a Tenth Spring map store.
Guarded by memguard step 'measure_synth'.
Contract: docs/implementation_plan_world_generation_slice2.md §10.3 & docs/agent_execution_guide.md §2 Item 13.
"""

import argparse
import os
import shutil
import subprocess
import sys

def parse_args():
    parser = argparse.ArgumentParser(
        description="Measure synthesis statistics on a Tenth Spring map store."
    )
    parser.add_argument(
        "--store",
        required=True,
        help="Path to map store SQLite file (e.g. user://measure_dc/district-of-columbia-261001.db)."
    )
    return parser.parse_args()

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    # Memory Guard check: ensure execution runs under memguard step 'measure_synth'
    if not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        memguard_script = os.path.join(repo_root, "tools", "memguard.py")
        cmd = [
            sys.executable,
            "-I",
            memguard_script,
            "run",
            "measure_synth",
            "--",
            sys.executable,
            "-I",
            os.path.abspath(__file__),
        ] + sys.argv[1:]
        res = subprocess.run(cmd)
        sys.exit(res.returncode)

    godot_bin = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot_bin:
        print("[FAIL] Godot executable not found in PATH or GODOT_BIN", file=sys.stderr)
        sys.exit(1)

    godot_cmd = [
        godot_bin,
        "--headless",
        "--path",
        "game",
        "res://scenes/measure_synth.tscn",
        "--",
        f"--store={args.store}"
    ]

    proc = subprocess.run(godot_cmd, cwd=repo_root, capture_output=True, text=True)
    if proc.returncode != 0:
        if proc.stderr:
            print(proc.stderr, file=sys.stderr, end="")
        if proc.stdout:
            print(proc.stdout, file=sys.stderr, end="")
        sys.exit(proc.returncode)

    # Print only the MEASURE line
    measure_line = None
    for line in proc.stdout.splitlines():
        if line.startswith("MEASURE "):
            measure_line = line
            break

    if measure_line:
        print(measure_line)
    else:
        print(f"[FAIL] No MEASURE line produced by measure_synth. Output:\n{proc.stdout}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
