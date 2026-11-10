#!/usr/bin/env python3
import argparse
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time

def parse_args():
    parser = argparse.ArgumentParser(
        description="Import explore points into the Tenth Spring demo profile."
    )
    parser.add_argument(
        "--points",
        required=True,
        help="Path to external JSON points file to import (must reside outside repository tree)."
    )
    parser.add_argument(
        "--demo-dir",
        default=None,
        help="Optional custom demo directory (e.g., user://test/demo). Defaults to user://demo."
    )
    parser.add_argument(
        "--port",
        type=int,
        default=7352,
        help="Dedicated demo sync port (default: 7352)."
    )
    return parser.parse_args()

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    # 1. Enforce Repo Isolation Rule (Standing Constraint 5)
    # Refuses execution if points file resides inside repository tree.
    # Exits with returncode 2 before running memguard or launching any process.
    points_path = os.path.abspath(args.points)
    real_points = os.path.realpath(points_path)
    real_repo = os.path.realpath(repo_root)

    try:
        common = os.path.commonpath([real_points, real_repo])
    except ValueError:
        common = ""

    if common == real_repo:
        print(
            f"[FAIL] Repo Isolation Rule: points file must be outside Tenth Spring repository tree: {points_path}",
            file=sys.stderr
        )
        sys.exit(2)

    if not os.path.isfile(real_points):
        print(f"[FAIL] Points file not found: {points_path}", file=sys.stderr)
        sys.exit(1)

    # 2. Memory Guard check: ensure execution runs under memguard demo_import step
    if not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        memguard_script = os.path.join(repo_root, "tools", "memguard.py")
        cmd = [
            sys.executable,
            "-I",
            memguard_script,
            "run",
            "demo_import",
            "--",
            sys.executable,
            "-I",
            os.path.abspath(__file__),
        ] + sys.argv[1:]
        res = subprocess.run(cmd)
        sys.exit(res.returncode)

    godot_wrapper = os.path.join(repo_root, "tools", "godot.py")

    print("=== Tenth Spring Demo Explore Points Importer ===")
    print(f"Points: {real_points}")

    # 3. Run Godot demo import scene headlessly
    godot_cmd = [
        sys.executable,
        "-I",
        godot_wrapper,
        "--memguard-step",
        "demo_import",
        "res://scenes/demo_import_server.tscn",
        "--",
    ]
    if args.demo_dir:
        godot_cmd.append(f"--demo-dir={args.demo_dir}")
    else:
        godot_cmd.append("--demo")
    godot_cmd.append(f"--points={real_points}")

    res = subprocess.run(
        godot_cmd,
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=120
    )

    out_text = (res.stdout or "") + "\n" + (res.stderr or "")
    if res.returncode != 0:
        print(f"[FAIL] Godot demo import exited with code {res.returncode}", file=sys.stderr)
        print(out_text, file=sys.stderr)
        sys.exit(res.returncode if res.returncode in (75, 76) else 1)

    applied_rows = None
    for line in out_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("DEMO_IMPORT_COMPLETE applied "):
            parts = stripped.split()
            applied_rows = int(parts[2])
            break

    if applied_rows is None:
        print("[FAIL] Did not receive DEMO_IMPORT_COMPLETE from Godot", file=sys.stderr)
        print(out_text, file=sys.stderr)
        sys.exit(1)

    print(f"Imported {applied_rows} explore/home events into demo profile.")
    sys.exit(0)

if __name__ == "__main__":
    main()
