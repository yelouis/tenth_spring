#!/usr/bin/env python3
"""
tools/check_caricature.py — Compile and check caricature maps against playable-size rules (P1–P7).
Guarded by memguard step 'check_caricature'.
Contract: docs/implementation_plan_dc_trial.md §5.3 & docs/agent_execution_guide.md §5.
"""

import argparse
import os
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Compile and check Tenth Spring caricature maps (P1–P7)."
    )
    parser.add_argument(
        "--area",
        type=str,
        default=None,
        help="Optional area id (e.g. hood:washington-dc:dupont-circle). Omit to check all areas in roster.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Print the compiled map as text.",
    )
    parser.add_argument(
        "--roster",
        type=str,
        default="res://config/neighbourhoods.json",
        help="Roster resource path (default: res://config/neighbourhoods.json).",
    )
    return parser.parse_args()


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    if not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        memguard_script = os.path.join(repo_root, "tools", "memguard.py")
        cmd = [
            sys.executable,
            "-I",
            memguard_script,
            "run",
            "check_caricature",
            "--",
            sys.executable,
            "-I",
            os.path.abspath(__file__),
        ] + sys.argv[1:]
        res = subprocess.run(cmd)
        sys.exit(res.returncode)

    godot_wrapper = os.path.join(repo_root, "tools", "godot.py")
    godot_cmd = [
        sys.executable,
        "-I",
        godot_wrapper,
        "--memguard-step",
        "check_caricature",
        "res://scenes/check_caricature.tscn",
        "--",
        f"--roster={args.roster}",
    ]
    if args.area is not None:
        godot_cmd.append(f"--area={args.area}")
    if args.preview:
        godot_cmd.append("--preview")

    proc = subprocess.run(godot_cmd, cwd=repo_root, capture_output=True, text=True)

    produced_caricature_line = False
    for line in proc.stdout.splitlines():
        if line.startswith(("CARICATURE ", "CARICATURE_ROUTE ", "CARICATURE_CITY ")):
            print(line)
            produced_caricature_line = True
        elif line.startswith("PREVIEW:"):
            print(line[len("PREVIEW:") :])

    if proc.returncode != 0:
        if proc.stderr:
            for err_line in proc.stderr.splitlines():
                if "[FAIL]" in err_line or "SCRIPT ERROR" in err_line or "ERROR:" in err_line:
                    print(err_line, file=sys.stderr)
        if not produced_caricature_line and not proc.stderr:
            print(proc.stdout, file=sys.stderr, end="")
        sys.exit(proc.returncode)

    if not produced_caricature_line:
        print(
            f"[FAIL] No CARICATURE line produced by check_caricature. Output:\n{proc.stdout}",
            file=sys.stderr,
        )
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
