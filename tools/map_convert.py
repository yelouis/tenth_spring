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
        default=None,
        help="Path to .osm.pbf regional extract file."
    )
    parser.add_argument(
        "--out-dir",
        default="user://map_data",
        help="Target output directory (default: user://map_data)."
    )
    parser.add_argument(
        "--clip-to-save",
        default=None,
        help="Path to save database for clip conversion (e.g. user://demo/tenth_spring.db)."
    )
    parser.add_argument(
        "--place",
        default=None,
        help="Convert a famous place (e.g. city:washington-dc)."
    )
    parser.add_argument(
        "--config",
        default=None,
        help="Path to famous places JSON config."
    )
    parser.add_argument(
        "--margin-cells",
        type=int,
        default=6,
        help="Margin around revealed cells for clip conversion (default: 6)."
    )
    parser.add_argument(
        "--print-region",
        default=None,
        help="Print region matching revealed cells in save database and exit."
    )
    return parser.parse_args()

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    godot_bin = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot_bin:
        print("[FAIL] Godot executable not found in PATH or GODOT_BIN", file=sys.stderr)
        sys.exit(1)

    if args.print_region:
        godot_cmd = [
            godot_bin,
            "--headless",
            "--path",
            "game",
            "res://scenes/map_convert.tscn",
            "--",
            f"--print-region={args.print_region}"
        ]
        res = subprocess.run(godot_cmd, cwd=repo_root)
        sys.exit(res.returncode)

    if not args.pbf:
        print("[FAIL] Missing required argument --pbf (or --print-region)", file=sys.stderr)
        sys.exit(1)

    pbf_path = os.path.abspath(args.pbf)
    if not os.path.isfile(pbf_path):
        print(f"[FAIL] PBF file not found: {pbf_path}", file=sys.stderr)
        sys.exit(1)

    # Determine memguard step: map_convert_clip if clipping or converting place, else map_convert
    step = "map_convert_clip" if (args.clip_to_save or args.place) else "map_convert"

    # Memory Guard check: ensure execution runs under memguard
    if not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        memguard_script = os.path.join(repo_root, "tools", "memguard.py")
        cmd = [
            sys.executable,
            "-I",
            memguard_script,
            "run",
            step,
            "--",
            sys.executable,
            "-I",
            os.path.abspath(__file__),
        ] + sys.argv[1:]
        res = subprocess.run(cmd)
        sys.exit(res.returncode)

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
    if args.place:
        godot_cmd.append(f"--place={args.place}")
    if args.config:
        godot_cmd.append(f"--config={args.config}")
    if args.clip_to_save:
        godot_cmd.append(f"--clip-to-save={args.clip_to_save}")
        godot_cmd.append(f"--margin-cells={args.margin_cells}")

    res = subprocess.run(godot_cmd, cwd=repo_root)
    sys.exit(res.returncode)

if __name__ == "__main__":
    main()
