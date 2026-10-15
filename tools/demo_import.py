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
        description="Import a hand-drawn or recorded GPX route into the Tenth Spring demo profile."
    )
    parser.add_argument(
        "--gpx",
        required=True,
        help="Path to external GPX file to import (must reside outside repository tree)."
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
    # Refuses execution if GPX resides inside repository tree.
    # Exits with returncode 2 before running memguard or launching any process.
    gpx_path = os.path.abspath(args.gpx)
    real_gpx = os.path.realpath(gpx_path)
    real_repo = os.path.realpath(repo_root)

    try:
        common = os.path.commonpath([real_gpx, real_repo])
    except ValueError:
        common = ""

    if common == real_repo:
        print(
            f"[FAIL] Repo Isolation Rule: GPX file must be outside Tenth Spring repository tree: {gpx_path}",
            file=sys.stderr
        )
        sys.exit(2)

    if not os.path.isfile(real_gpx):
        print(f"[FAIL] GPX file not found: {gpx_path}", file=sys.stderr)
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

    game_dir = os.path.join(repo_root, "game")
    companion_dir = os.path.join(repo_root, "companion")

    godot_bin = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot_bin:
        print("[FAIL] Godot executable not found in PATH or GODOT_BIN", file=sys.stderr)
        sys.exit(1)

    flutter_bin = os.environ.get("FLUTTER_BIN") or shutil.which("flutter")
    if not flutter_bin:
        print("[FAIL] Flutter executable not found in PATH or FLUTTER_BIN", file=sys.stderr)
        sys.exit(1)

    print(f"=== Tenth Spring Demo GPX Importer ===")
    print(f"GPX: {real_gpx}")
    print(f"Port: {args.port}")

    # 3. Start Godot demo import server scene
    godot_cmd = [godot_bin, "--headless", "--path", "game", "res://scenes/demo_import_server.tscn", "--"]
    if args.demo_dir:
        godot_cmd.append(f"--demo-dir={args.demo_dir}")
    else:
        godot_cmd.append("--demo")
    godot_cmd.append(f"--port={args.port}")

    godot_proc = subprocess.Popen(
        godot_cmd,
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )

    out_q = queue.Queue()
    def enqueue_output(out, q):
        try:
            for line in iter(out.readline, ''):
                q.put(line)
        finally:
            out.close()

    reader_thread = threading.Thread(target=enqueue_output, args=(godot_proc.stdout, out_q), daemon=True)
    reader_thread.start()

    ready_data = None
    start_time = time.time()

    # Wait up to 60s for DEMO_READY
    while time.time() - start_time < 60.0:
        if godot_proc.poll() is not None and out_q.empty():
            print(f"[FAIL] Godot server exited prematurely with code {godot_proc.returncode}", file=sys.stderr)
            sys.exit(1)
        try:
            line = out_q.get(timeout=1.0)
            stripped = line.strip()
            if stripped.startswith("DEMO_READY "):
                json_str = stripped[len("DEMO_READY "):].strip()
                ready_data = json.loads(json_str)
                break
        except queue.Empty:
            continue

    if not ready_data:
        print("[FAIL] Timeout waiting for DEMO_READY from Godot server", file=sys.stderr)
        godot_proc.kill()
        sys.exit(1)

    print(f"Demo server ready on port {ready_data['port']} with fingerprint {ready_data['fp'][:16]}...")

    # 4. Invoke companion replay/sync pipeline headlessly
    flutter_cmd = [
        flutter_bin,
        "test",
        "test/demo_import_test.dart",
        f"--dart-define=DEMO_GPX={real_gpx}",
        f"--dart-define=DEMO_PORT={ready_data['port']}",
        f"--dart-define=DEMO_FP={ready_data['fp']}",
        f"--dart-define=DEMO_PAIR={ready_data['pair']}",
        f"--dart-define=DEMO_PC_ID={ready_data['pcId']}",
    ]

    flutter_res = subprocess.run(
        flutter_cmd,
        cwd=companion_dir,
        capture_output=True,
        text=True
    )

    if flutter_res.returncode != 0:
        print(f"[FAIL] Companion demo import test failed with code {flutter_res.returncode}", file=sys.stderr)
        if flutter_res.stdout:
            print(flutter_res.stdout)
        if flutter_res.stderr:
            print(flutter_res.stderr, file=sys.stderr)
        godot_proc.kill()
        sys.exit(1)

    sent_data = None
    for line in flutter_res.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("DEMO_SENT "):
            sent_data = json.loads(stripped[len("DEMO_SENT "):].strip())
            break

    if not sent_data:
        print("[FAIL] Could not find DEMO_SENT line in companion output", file=sys.stderr)
        godot_proc.kill()
        sys.exit(1)

    sent_rows = int(sent_data.get("rows", 0))

    # 5. Wait for DEMO_IMPORT_COMPLETE from Godot
    applied_rows = None
    wait_import_start = time.time()

    while time.time() - wait_import_start < 30.0:
        try:
            line = out_q.get(timeout=1.0)
            stripped = line.strip()
            if stripped.startswith("DEMO_IMPORT_COMPLETE applied "):
                parts = stripped.split()
                # format: DEMO_IMPORT_COMPLETE applied <N> rows
                applied_rows = int(parts[2])
                break
        except queue.Empty:
            if godot_proc.poll() is not None and out_q.empty():
                break

    godot_proc.wait(timeout=10.0)

    if godot_proc.returncode != 0:
        print(f"[FAIL] Godot server exited with code {godot_proc.returncode}", file=sys.stderr)
        sys.exit(1)

    if applied_rows is None:
        print("[FAIL] Timeout waiting for DEMO_IMPORT_COMPLETE from Godot server", file=sys.stderr)
        sys.exit(1)

    # 6. Verify applied count equals DEMO_SENT
    if applied_rows != sent_rows:
        print(f"[FAIL] Applied rows ({applied_rows}) != DEMO_SENT ({sent_rows})", file=sys.stderr)
        sys.exit(1)

    print(f"Imported {applied_rows} scout points into demo profile.")
    sys.exit(0)

if __name__ == "__main__":
    main()
