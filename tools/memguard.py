#!/usr/bin/env python3
"""
Tenth Spring — Developer Tooling Memory Guard (tools/memguard.py)
Contract: docs/design_memory_and_resources.md §1, §2, §4

Admits, serializes, and watches heavy developer commands (Godot, Flutter, spikes).
Pure Python 3 standard library; runs under python3 -I.
"""

import datetime
import fcntl
import json
import math
import os
import platform
import re
import signal
import subprocess
import sys
import time

# --- Constants (design_memory_and_resources.md §2) ---
FLOOR_MIN_BYTES = 4 * 1024 * 1024 * 1024  # 4 GiB
FLOOR_RATIO = 0.10  # 10% of total RAM
POLL_SECONDS = 2.0
ADMIT_TIMEOUT = 15 * 60.0  # 15 minutes
STOP_GRACE = 10.0  # 10 seconds (SIGTERM -> SIGKILL)
RUNAWAY_FACTOR = 1.5
BUDGET_MARGIN = 1.25
DEFAULT_UNMEASURED_BUDGET_GIB = 8.0

EXIT_ADMIT_TIMEOUT = 75
EXIT_STOPPED_BY_GUARD = 76

ENV_MEMGUARD_HELD = "TENTH_SPRING_MEMGUARD_HELD"
ENV_LOCK_DIR = "TENTH_SPRING_LOCK_DIR"
ENV_LOG_DIR = "TENTH_SPRING_LOG_DIR"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUDGETS_FILE = os.path.join(REPO_ROOT, "tools", "memguard_budgets.json")

# --- Injections for testing ---
_reader_override = None
_clock_override = None
_sleep_override = None


class MemoryInfo:
    def __init__(self, available_bytes=None, total_bytes=None, pressure_level=None):
        self.available_bytes = available_bytes
        self.total_bytes = total_bytes
        self.pressure_level = pressure_level

    def __repr__(self):
        return (
            f"MemoryInfo(avail={self.available_bytes}, total={self.total_bytes}, "
            f"pressure={self.pressure_level})"
        )


def set_memory_reader(fn):
    global _reader_override
    _reader_override = fn


def set_clock(fn):
    global _clock_override
    _clock_override = fn


def set_sleep(fn):
    global _sleep_override
    _sleep_override = fn


def reset_injections():
    global _reader_override, _clock_override, _sleep_override
    _reader_override = None
    _clock_override = None
    _sleep_override = None


def now() -> float:
    if _clock_override is not None:
        return _clock_override()
    return time.time()


def sleep(seconds: float) -> None:
    if _sleep_override is not None:
        _sleep_override(seconds)
    else:
        time.sleep(seconds)


def get_floor_bytes(total_bytes: int | None) -> int:
    if total_bytes is not None and total_bytes > 0:
        return max(FLOOR_MIN_BYTES, int(total_bytes * FLOOR_RATIO))
    return FLOOR_MIN_BYTES


def _read_macos_memory() -> MemoryInfo:
    total_bytes = None
    try:
        res = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, check=False)
        if res.returncode == 0 and res.stdout.strip():
            total_bytes = int(res.stdout.strip())
    except Exception:
        pass

    pressure_level = 1
    try:
        res = subprocess.run(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"], capture_output=True, text=True, check=False)
        if res.returncode == 0 and res.stdout.strip():
            pressure_level = int(res.stdout.strip())
    except Exception:
        pass

    available_bytes = None
    try:
        res = subprocess.run(["vm_stat"], capture_output=True, text=True, check=False)
        if res.returncode == 0 and res.stdout:
            out = res.stdout
            pg_match = re.search(r"page size of (\d+) bytes", out)
            page_size = int(pg_match.group(1)) if pg_match else 4096

            stats = {}
            for line in out.splitlines():
                m = re.match(r"^\"?([^\":]+)\"?:?\s+(\d+)\.", line.strip())
                if m:
                    stats[m.group(1)] = int(m.group(2))

            free = stats.get("Pages free", 0)
            inactive = stats.get("Pages inactive", 0)
            speculative = stats.get("Pages speculative", 0)
            purgeable = stats.get("Pages purgeable", 0)
            available_bytes = (free + inactive + speculative + purgeable) * page_size
    except Exception:
        pass

    return MemoryInfo(available_bytes=available_bytes, total_bytes=total_bytes, pressure_level=pressure_level)


def _read_linux_memory() -> MemoryInfo:
    total_bytes = None
    available_bytes = None
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    key = parts[0].rstrip(":")
                    val_kb = int(parts[1])
                    if key == "MemTotal":
                        total_bytes = val_kb * 1024
                    elif key == "MemAvailable":
                        available_bytes = val_kb * 1024
    except Exception:
        pass

    pressure_level = 1
    if available_bytes is not None and total_bytes is not None:
        floor = get_floor_bytes(total_bytes)
        pressure_level = 4 if available_bytes < floor else 1

    return MemoryInfo(available_bytes=available_bytes, total_bytes=total_bytes, pressure_level=pressure_level)


_unreadable_warned = False


def read_memory() -> MemoryInfo:
    global _unreadable_warned
    if _reader_override is not None:
        return _reader_override()

    plat = sys.platform
    if plat == "darwin":
        return _read_macos_memory()
    elif plat.startswith("linux"):
        return _read_linux_memory()
    else:
        if not _unreadable_warned:
            print(f"memguard: memory unreadable on {plat} — lock only", file=sys.stderr)
            _unreadable_warned = True
        return MemoryInfo(available_bytes=None, total_bytes=None, pressure_level=None)


def get_process_tree_rss(root_pid: int) -> int:
    try:
        res = subprocess.run(
            ["ps", "-A", "-o", "pid=,ppid=,rss="],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )
    except Exception:
        return 0

    if res.returncode != 0 or not res.stdout:
        return 0

    tree = {}
    for line in res.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 3:
            try:
                pid = int(parts[0])
                ppid = int(parts[1])
                rss_kb = int(parts[2])
                tree[pid] = (ppid, rss_kb)
            except ValueError:
                continue

    if root_pid not in tree:
        return 0

    descendants = {root_pid}
    added = True
    while added:
        added = False
        for pid, (ppid, _) in tree.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                added = True

    total_rss_bytes = sum(tree[pid][1] * 1024 for pid in descendants if pid in tree)
    return total_rss_bytes


def get_lock_dir() -> str:
    override = os.environ.get(ENV_LOCK_DIR)
    if override:
        return override
    return os.path.expanduser("~/.cache/tenth_spring/locks")


def get_lock_file() -> str:
    return os.path.join(get_lock_dir(), "heavy.lock")


def get_log_file() -> str:
    if os.environ.get(ENV_LOG_DIR):
        return os.path.join(os.environ[ENV_LOG_DIR], "memguard.log")
    if os.environ.get(ENV_LOCK_DIR):
        return os.path.join(os.path.dirname(get_lock_dir()), "memguard.log")
    return os.path.expanduser("~/.cache/tenth_spring/memguard.log")


def _log_run(step: str, budget: float, peak: float, waited_ms: int, outcome: str):
    log_path = get_log_file()
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        record = {
            "step": step,
            "budget": round(budget, 3),
            "peak": round(peak, 3),
            "waited_ms": waited_ms,
            "outcome": outcome,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
        }
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")
    except Exception as e:
        print(f"memguard: failed to append to log {log_path}: {e}", file=sys.stderr)


def load_budgets() -> dict:
    if os.path.isfile(BUDGETS_FILE):
        try:
            with open(BUDGETS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"memguard: failed reading {BUDGETS_FILE}: {e}", file=sys.stderr)
    return {}


def save_budgets(budgets: dict):
    try:
        os.makedirs(os.path.dirname(BUDGETS_FILE), exist_ok=True)
        with open(BUDGETS_FILE, "w", encoding="utf-8") as f:
            json.dump(budgets, f, indent=2)
            f.write("\n")
    except Exception as e:
        print(f"memguard: failed writing {BUDGETS_FILE}: {e}", file=sys.stderr)


def get_step_budget(step: str) -> tuple[float, bool]:
    budgets = load_budgets()
    entry = budgets.get(step)
    if entry is not None:
        if isinstance(entry, dict):
            b = float(entry.get("budget_gib", DEFAULT_UNMEASURED_BUDGET_GIB))
            is_unmeasured = entry.get("status") == "UNMEASURED"
            return b, is_unmeasured
        elif isinstance(entry, (int, float)):
            return float(entry), False
    return DEFAULT_UNMEASURED_BUDGET_GIB, True


def run_guarded(
    step: str,
    cmd: list[str],
    admit_timeout: float = ADMIT_TIMEOUT,
    poll_seconds: float = POLL_SECONDS,
    stop_grace: float = STOP_GRACE,
    runaway_factor: float = RUNAWAY_FACTOR,
    override_budget_gib: float | None = None,
    allow_rss_check: bool = True
) -> int:
    """Executes cmd guarded by admission, machine-wide serialization, and watchdog."""
    # Nested run bypass
    if os.environ.get(ENV_MEMGUARD_HELD):
        res = subprocess.run(cmd)
        return res.returncode

    if override_budget_gib is not None:
        budget_gib = override_budget_gib
        is_unmeasured = False
    else:
        budget_gib, is_unmeasured = get_step_budget(step)

    if is_unmeasured:
        print(f"memguard: WARNING: step '{step}' is UNMEASURED — using {budget_gib:.1f} GiB default budget", file=sys.stderr)

    lock_file = get_lock_file()
    os.makedirs(os.path.dirname(lock_file), exist_ok=True)

    wait_start = now()
    lock_fd = open(lock_file, "a+")

    try:
        # 1. Acquire machine-wide exclusive lock
        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)
        try:
            lock_fd.seek(0)
            lock_fd.truncate()
            lock_fd.write(f"{os.getpid()}\n")
            lock_fd.flush()
        except Exception:
            pass

        # 2. Wait for room (admission)
        last_log_time = wait_start
        while True:
            mem = read_memory()
            if mem.available_bytes is None:
                # Platform unreadable: serialize with lock only
                break

            floor_bytes = get_floor_bytes(mem.total_bytes)
            budget_bytes = int(budget_gib * (1024**3))
            required_bytes = budget_bytes + floor_bytes

            if mem.available_bytes >= required_bytes and (mem.pressure_level is None or mem.pressure_level < 4):
                # Room admitted
                break

            elapsed = now() - wait_start
            if elapsed >= admit_timeout:
                need_gib = required_bytes / (1024**3)
                have_gib = mem.available_bytes / (1024**3)
                msg = (
                    f"memguard: not enough free memory for {step} "
                    f"(need {need_gib:.1f} GiB, have {have_gib:.1f} GiB) — "
                    f"other programs are using it; close some or try later"
                )
                print(msg, file=sys.stderr)
                _log_run(step, budget_gib, 0.0, int(elapsed * 1000), "timeout")
                sys.exit(EXIT_ADMIT_TIMEOUT)

            if elapsed - last_log_time >= 30.0:
                last_log_time = elapsed
                need_gib = required_bytes / (1024**3)
                have_gib = mem.available_bytes / (1024**3)
                print(
                    f"memguard: waiting for memory for {step}: need {need_gib:.1f} GiB, have {have_gib:.1f} GiB",
                    file=sys.stderr
                )

            sleep(poll_seconds)

        waited_ms = int((now() - wait_start) * 1000)

        # 3. Launch child in own process group and run watchdog
        child_env = os.environ.copy()
        child_env[ENV_MEMGUARD_HELD] = step

        proc = subprocess.Popen(cmd, start_new_session=True, env=child_env)

        critical_pressure_count = 0
        peak_rss = 0
        budget_bytes = int(budget_gib * (1024**3))

        while proc.poll() is None:
            sleep(poll_seconds)

            current_rss = get_process_tree_rss(proc.pid)
            if current_rss > peak_rss:
                peak_rss = current_rss

            mem = read_memory()
            cause = None

            if mem.pressure_level is not None and mem.pressure_level >= 4:
                critical_pressure_count += 1
                if critical_pressure_count >= 2:
                    cause = "critical memory pressure"
            else:
                critical_pressure_count = 0

            if not cause and mem.available_bytes is not None:
                floor_bytes = get_floor_bytes(mem.total_bytes)
                if mem.available_bytes < (floor_bytes / 2):
                    cause = "available below floor"

            if not cause and allow_rss_check:
                if current_rss > budget_bytes * runaway_factor:
                    cause = "tree RSS exceeded budget"

            if cause:
                # Stop the whole process group
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

                grace_start = now()
                while now() - grace_start < stop_grace:
                    if proc.poll() is not None:
                        break
                    sleep(0.2)

                if proc.poll() is None:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    try:
                        proc.wait(timeout=5.0)
                    except Exception:
                        pass

                peak_gib = peak_rss / (1024**3)
                print(f"memguard: stopped {step} — {cause}; peak {peak_gib:.1f} GiB", file=sys.stderr)
                _log_run(step, budget_gib, peak_gib, waited_ms, f"stopped:{cause}")
                sys.exit(EXIT_STOPPED_BY_GUARD)

        proc.wait()
        peak_gib = peak_rss / (1024**3)
        outcome = "ok" if proc.returncode == 0 else f"failed:{proc.returncode}"
        _log_run(step, budget_gib, peak_gib, waited_ms, outcome)

        return proc.returncode
    finally:
        try:
            fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
        try:
            lock_fd.close()
        except Exception:
            pass


def measure_step(step: str, cmd: list[str]) -> int:
    """Measures peak process-tree RSS and updates memguard_budgets.json."""
    lock_file = get_lock_file()
    os.makedirs(os.path.dirname(lock_file), exist_ok=True)
    lock_fd = open(lock_file, "a+")
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)

    child_env = os.environ.copy()
    child_env[ENV_MEMGUARD_HELD] = step

    proc = subprocess.Popen(cmd, start_new_session=True, env=child_env)
    peak_rss = 0

    while proc.poll() is None:
        sleep(0.2)
        rss = get_process_tree_rss(proc.pid)
        if rss > peak_rss:
            peak_rss = rss

    proc.wait()
    try:
        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
        lock_fd.close()
    except Exception:
        pass

    if proc.returncode != 0:
        print(f"memguard measure: command failed with returncode {proc.returncode}", file=sys.stderr)
        return proc.returncode

    peak_gib = round(peak_rss / (1024**3), 3)
    margin_budget = peak_gib * BUDGET_MARGIN
    budget_gib = math.ceil(margin_budget * 2.0) / 2.0
    if budget_gib < 0.5:
        budget_gib = 0.5

    budgets = load_budgets()
    budgets[step] = {
        "budget_gib": budget_gib,
        "peak_gib": peak_gib,
        "date": datetime.date.today().isoformat(),
        "machine": f"{platform.system().lower()} {platform.machine()}",
        "status": "measured"
    }
    save_budgets(budgets)
    print(f"memguard: measured {step}: peak {peak_gib:.3f} GiB, budget {budget_gib:.1f} GiB (written to tools/memguard_budgets.json)")
    return 0


def cmd_doctor() -> int:
    print("=== memguard doctor ===")
    mem = read_memory()
    plat = platform.system().lower()
    mach = platform.machine()
    print(f"Platform: {plat} ({mach})")

    if mem.total_bytes is not None:
        total_gib = mem.total_bytes / (1024**3)
        print(f"Total RAM: {total_gib:.1f} GiB")
    else:
        print("Total RAM: unknown")

    if mem.available_bytes is not None and mem.total_bytes is not None:
        avail_gib = mem.available_bytes / (1024**3)
        avail_pct = (mem.available_bytes / mem.total_bytes) * 100
        print(f"Available: {avail_gib:.1f} GiB ({avail_pct:.1f}%)")
    else:
        print("Available: unknown")

    floor_bytes = get_floor_bytes(mem.total_bytes)
    floor_gib = floor_bytes / (1024**3)
    print(f"Floor: {floor_gib:.1f} GiB")

    if mem.pressure_level is not None:
        print(f"Memory pressure level: {mem.pressure_level}")
    else:
        print("Memory pressure level: unknown")

    # Sanity check against memory_pressure -Q on macOS
    if plat == "darwin" and mem.available_bytes is not None and mem.total_bytes is not None:
        try:
            res = subprocess.run(["memory_pressure", "-Q"], capture_output=True, text=True, check=False)
            if res.returncode == 0 and res.stdout:
                m = re.search(r"percentage:\s*(\d+)%", res.stdout)
                if m:
                    free_pct = int(m.group(1))
                    avail_pct = (mem.available_bytes / mem.total_bytes) * 100
                    diff = abs(free_pct - avail_pct)
                    if diff > 10:
                        print(
                            f"Warning: available memory percentage ({avail_pct:.1f}%) disagrees with "
                            f"memory_pressure -Q free percentage ({free_pct}%) by > 10 points ({diff:.1f} points)"
                        )
                    else:
                        print(f"Cross-check OK: memory_pressure -Q ({free_pct}%) agrees with available ({avail_pct:.1f}%) within 10 points")
        except Exception as e:
            print(f"Could not run memory_pressure -Q: {e}")

    # Check lock holder
    lock_file = get_lock_file()
    holder_pid = None
    if os.path.isfile(lock_file):
        try:
            test_fd = open(lock_file, "a+")
            try:
                fcntl.flock(test_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(test_fd.fileno(), fcntl.LOCK_UN)
            except (BlockingIOError, IOError):
                test_fd.seek(0)
                line = test_fd.readline().strip()
                if line:
                    holder_pid = line
            finally:
                test_fd.close()
        except Exception:
            pass

    if holder_pid:
        print(f"Current lock holder: PID {holder_pid}")
    else:
        print("Current lock holder: None (lock is free)")

    # Budgets table
    print("\nConfigured Budgets:")
    budgets = load_budgets()
    if not budgets:
        print("  (no budgets configured)")
    else:
        print(f"  {'Step':<20} {'Budget':<10} {'Peak':<10} {'Status':<12} {'Machine'}")
        print(f"  {'-'*20} {'-'*10} {'-'*10} {'-'*12} {'-'*20}")
        for step, data in sorted(budgets.items()):
            if isinstance(data, dict):
                bg = f"{data.get('budget_gib', 8.0):.1f} GiB"
                pk = f"{data.get('peak_gib', 0.0):.3f} GiB" if "peak_gib" in data else "-"
                st = data.get("status", "measured")
                mc = data.get("machine", "-")
                print(f"  {step:<20} {bg:<10} {pk:<10} {st:<12} {mc}")
            else:
                print(f"  {step:<20} {float(data):.1f} GiB")

    return 0


def main():
    if len(sys.argv) < 2:
        print("Usage: memguard [run <step> -- <cmd...> | measure <step> -- <cmd...> | doctor]", file=sys.stderr)
        sys.exit(1)

    subcmd = sys.argv[1]
    if subcmd == "doctor":
        sys.exit(cmd_doctor())
    elif subcmd in ("run", "measure"):
        if len(sys.argv) < 3:
            print(f"Usage: memguard {subcmd} <step> -- <cmd...>", file=sys.stderr)
            sys.exit(1)
        step = sys.argv[2]
        if "--" not in sys.argv:
            print(f"Usage: memguard {subcmd} <step> -- <cmd...>", file=sys.stderr)
            sys.exit(1)
        dash_idx = sys.argv.index("--")
        cmd = sys.argv[dash_idx + 1 :]
        if not cmd:
            print(f"memguard {subcmd}: no command specified after '--'", file=sys.stderr)
            sys.exit(1)

        if subcmd == "run":
            code = run_guarded(step, cmd)
            sys.exit(code)
        else:
            code = measure_step(step, cmd)
            sys.exit(code)
    else:
        print(f"Unknown memguard command: {subcmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
