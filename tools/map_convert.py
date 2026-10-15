#!/usr/bin/env python3
"""
tools/map_convert.py — Standalone tool to convert regional OSM PBF extracts into map stores.
Guarded by memguard step 'map_convert'.
"""

import argparse
import os
import shutil
import subprocess
import sys

def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert regional OpenStreetMap PBF extract into Tenth Spring SQLite map store."
    )
    parser.add_argument(
        "--pbf",
        required=True,
        help="Path to .osm.pbf regional extract file."
    )
    parser.add_argument(
        "--out-dir",
        default="user://map_data",
        help="Target output directory (default: user://map_data)."
    )
    return parser.parse_args()

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    pbf_path = os.path.abspath(args.pbf)
    if not os.path.isfile(pbf_path):
        print(f"[FAIL] PBF file not found: {pbf_path}", file=sys.stderr)
        sys.exit(1)

    # Memory Guard check: ensure execution runs under memguard map_convert step
    if not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        memguard_script = os.path.join(repo_root, "tools", "memguard.py")
        cmd = [
            sys.executable,
            "-I",
            memguard_script,
            "run",
            "map_convert",
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
        "res://scenes/map_convert.tscn",
        "--",
        f"--pbf={pbf_path}",
        f"--out-dir={args.out_dir}"
    ]

    res = subprocess.run(godot_cmd, cwd=repo_root)
    sys.exit(res.returncode)

if __name__ == "__main__":
    main()
