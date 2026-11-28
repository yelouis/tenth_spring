#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Seed a Tenth Spring demo profile with a starter city and optional opened places."
    )
    parser.add_argument(
        "--starter",
        required=True,
        help="Starter city place id (e.g., city:washington-dc).",
    )
    parser.add_argument(
        "--open",
        default="",
        help="Optional comma-separated list of place ids to open (e.g., site:yellowstone,city:boston).",
    )
    parser.add_argument(
        "--demo-dir",
        default=None,
        help="Optional custom demo directory (e.g., user://test/demo_ci). Defaults to user://demo.",
    )
    return parser.parse_args()


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = parse_args()

    # Memory Guard check: ensure execution runs under memguard demo_import step
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

    print("=== Tenth Spring Demo Profile Importer ===")
    print(f"Starter: {args.starter}")
    if args.open:
        print(f"Open: {args.open}")

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
    godot_cmd.append(f"--starter={args.starter}")
    if args.open:
        godot_cmd.append(f"--open={args.open}")

    res = subprocess.run(
        godot_cmd,
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=120,
    )

    out_text = (res.stdout or "") + "\n" + (res.stderr or "")
    if res.returncode != 0:
        for line in out_text.splitlines():
            if line.strip().startswith("[FAIL]"):
                print(line.strip(), file=sys.stderr)
        if res.returncode == 2:
            sys.exit(2)
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

    print(f"Imported {applied_rows} place events into demo profile.")
    sys.exit(0)


if __name__ == "__main__":
    main()
