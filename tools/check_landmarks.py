#!/usr/bin/env python3
"""
tools/check_landmarks.py — Standalone tool to verify landmark placement and gilding on a place store.
Guarded by memguard step 'check_landmarks'.
Contract: docs/implementation_plan_world_generation_slice2.md §11.1 & docs/agent_execution_guide.md §4.
"""

import argparse
import os
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Verify landmark placement and gilding on a Tenth Spring place store."
    )
    parser.add_argument(
        "--store",
        required=True,
        help="Path to place map store SQLite file (e.g. user://demo_dc/map_data/city:washington-dc.db).",
    )
    parser.add_argument(
        "--place",
        required=True,
        help="Place id from famous_places.json (e.g. city:washington-dc).",
    )
    return parser.parse_args()


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    godot_wrapper = os.path.join(repo_root, "tools", "godot.py")
    godot_cmd = [
        sys.executable,
        "-I",
        godot_wrapper,
        "--memguard-step",
        "check_landmarks",
        "res://scenes/check_landmarks.tscn",
        "--",
        f"--store={args.store}",
        f"--place={args.place}",
    ]

    proc = subprocess.run(godot_cmd, cwd=repo_root, capture_output=True, text=True)
    if proc.returncode != 0:
        if proc.stderr:
            print(proc.stderr, file=sys.stderr, end="")
        if proc.stdout:
            print(proc.stdout, file=sys.stderr, end="")
        sys.exit(proc.returncode)

    landmark_lines = [
        line for line in proc.stdout.splitlines() if line.startswith("LANDMARK ")
    ]
    if not landmark_lines:
        print(
            f"[FAIL] No LANDMARK lines produced by check_landmarks. Output:\n{proc.stdout}",
            file=sys.stderr,
        )
        sys.exit(1)

    for line in landmark_lines:
        print(line)


if __name__ == "__main__":
    main()
