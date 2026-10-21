#!/usr/bin/env python3
"""
tools/demo_screenshot.py — Capture map view screenshot harness.
Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6
"""

import argparse
import os
import shutil
import subprocess
import sys

def parse_args():
    parser = argparse.ArgumentParser(
        description="Capture windowed screenshots of the Tenth Spring map view."
    )
    parser.add_argument(
        "--out-dir",
        required=True,
        help="Directory to save screenshots (must be outside repository tree)."
    )
    parser.add_argument(
        "--zoom",
        type=str,
        action="append",
        dest="zooms",
        help="Zoom level to capture (can be specified multiple times, e.g. --zoom 1 --zoom 0.0625). Defaults to ['1']."
    )
    parser.add_argument(
        "--preview-cleared",
        action="store_true",
        help="Preview cleared look in demo mode."
    )
    parser.add_argument(
        "--demo-dir",
        type=str,
        default=None,
        help="Optional custom demo directory (e.g., user://demo_dc). Passed through to Godot."
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=10,
        help="Number of frames to wait after settling before capturing screenshot (default: 10)."
    )
    return parser.parse_args()

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    # 1. Enforce Repo Isolation Rule: out-dir must be outside repository tree (exit 2)
    out_dir = os.path.abspath(args.out_dir)
    real_out = os.path.realpath(out_dir)
    real_repo = os.path.realpath(repo_root)

    try:
        common = os.path.commonpath([real_out, real_repo])
    except ValueError:
        common = ""

    if common == real_repo:
        print(
            f"[FAIL] screenshot path must be outside the repository: {out_dir}",
            file=sys.stderr
        )
        sys.exit(2)

    os.makedirs(real_out, exist_ok=True)

    # 2. Memory Guard check: ensure execution runs under memguard demo_screenshot step
    if not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        memguard_script = os.path.join(repo_root, "tools", "memguard.py")
        cmd = [
            sys.executable,
            "-I",
            memguard_script,
            "run",
            "demo_screenshot",
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

    zooms = args.zooms if args.zooms else ["1"]

    for z in zooms:
        suffix = "_cleared" if args.preview_cleared else ""
        out_png = os.path.join(real_out, f"shot_z{z}{suffix}.png")
        godot_cmd = [
            godot_bin,
            "--path",
            "game",
            "--resolution",
            "1280x720",
            "--",
            "--demo",
            f"--screenshot={out_png}",
            f"--zoom={z}",
            f"--frames={args.frames}",
        ]
        if args.demo_dir:
            godot_cmd.append(f"--demo-dir={args.demo_dir}")
        if args.preview_cleared:
            godot_cmd.append("--preview-cleared")
        print(f"Running screenshot capture at zoom {z}: {' '.join(godot_cmd)}")
        res = subprocess.run(godot_cmd, cwd=repo_root)
        if res.returncode != 0:
            print(f"[FAIL] Godot screenshot capture failed with code {res.returncode}", file=sys.stderr)
            sys.exit(res.returncode)
        if not os.path.isfile(out_png):
            print(f"[FAIL] Expected screenshot not found: {out_png}", file=sys.stderr)
            sys.exit(1)

    print("[DEMO SCREENSHOT OK] All requested screenshots captured successfully.")
    sys.exit(0)

if __name__ == "__main__":
    main()
