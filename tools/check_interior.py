#!/usr/bin/env python3
"""
tools/check_interior.py — Compile and check interior maps against playable rules (I1–I6).
Guarded by memguard step 'check_caricature'.
Contract: docs/implementation_plan_dc_trial.md §11.3 C & docs/agent_execution_guide.md §5.
"""

import argparse
import os
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Compile and check Tenth Spring interior maps (I1–I6)."
    )
    parser.add_argument(
        "--interior",
        type=str,
        default=None,
        help="Optional interior id (e.g. dc:washington-monument). Omit to check all DC interiors.",
    )
    parser.add_argument(
        "--file",
        type=str,
        default=None,
        help="Optional explicit interior JSON path (for fixture / scratch checks).",
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
        "res://scenes/check_interior.tscn",
        "--",
    ]
    if args.interior is not None:
        godot_cmd.append(f"--interior={args.interior}")
    if args.file is not None:
        godot_cmd.append(f"--file={args.file}")

    proc = subprocess.run(godot_cmd, cwd=repo_root, capture_output=True, text=True)

    produced_interior_line = False
    for line in proc.stdout.splitlines():
        if line.startswith("INTERIOR "):
            print(line)
            produced_interior_line = True

    if proc.returncode != 0:
        if proc.stderr:
            for err_line in proc.stderr.splitlines():
                if "[FAIL]" in err_line or "SCRIPT ERROR" in err_line or "ERROR:" in err_line:
                    print(err_line, file=sys.stderr)
        if not produced_interior_line and not proc.stderr:
            print(proc.stdout, file=sys.stderr, end="")
        sys.exit(proc.returncode)

    if not produced_interior_line:
        print(
            f"[FAIL] No INTERIOR line produced by check_interior. Output:\n{proc.stdout}",
            file=sys.stderr,
        )
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
