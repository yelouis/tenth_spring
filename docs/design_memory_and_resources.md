# Memory & Resources — Never Run the Machine Out of Memory

This document defines how Tenth Spring — its developer tooling and the game itself — avoids exhausting memory on a machine it shares with programs it doesn't control. It was written on 2026-10-10 after the human asked for memory guards, following an out-of-memory event on the development Mac (64 GB) on 2026-10-09.

**What happened (for the record).** At 19:50–19:52 on 2026-10-09, macOS killed system services for lack of memory (`JetsamEvent` reports). The memory was held by two Python image-generation processes (~27–29 GB each) and a local language-model server (`llama-server`, ~11 GB), all from **another project** (`animated_infographics`), plus a browser. **No Tenth Spring process was running**; its last activity was nine hours earlier. The lesson still applies here: this project is about to run heavy work — converting regional map files of hundreds of MB, and importing a ROM — on a machine where other heavy programs start and stop at any time.

**The pillar:** *a check at start time is not enough.* Memory that is free when a job starts can be taken a minute later by another program. Every heavy operation therefore gets three protections:
1. **Bounded by construction** — it streams, so its peak memory doesn't grow with input size.
2. **Admitted only when there is room** — it waits for room instead of hoping.
3. **Watched while it runs** — it is paused or stopped cleanly, with its work resumable, if room disappears. The OS never gets to kill it mid-write.

---

## 1. Reading memory

| Where | How | Unknown? |
|---|---|---|
| Tooling on macOS | `vm_stat`: **available** = (free + inactive + speculative + purgeable) pages × page size. **Pressure** = `sysctl -n kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical). | — |
| Tooling on Linux (CI) | `/proc/meminfo` `MemAvailable` and `MemTotal`. Pressure = 4 if available < floor (§2), else 1. | — |
| Tooling elsewhere | Not measured: log `memguard: memory unreadable on <platform> — lock only`, and still serialize heavy steps with the lock. | yes |
| The game (GDScript) | `OS.get_memory_info()` → `available` and `physical` (bytes; available in Godot 4.3) | a value of `-1` → "can't measure": use the bounded design only, with no pause logic |

**Sanity check:** the tooling's `doctor` command compares its available-memory figure with `memory_pressure -Q`'s "free percentage" and warns if they disagree by more than 10 points.

## 2. Developer tooling guard — `tools/memguard.py` (stdlib only, `python3 -I`)

Every heavy command an agent or test runner starts — Godot runs, Flutter test runs, the sync end-to-end test, the demo import, the map-file speed spike, the ROM spike, iOS builds — goes through `memguard`. Nothing heavy runs outside it.

**Constants** (deliberate; change only with a measured reason):
- `FLOOR` = **max(4 GiB, 10% of total RAM)** — always left free for the OS and other programs.
- `POLL_SECONDS` = **2**.
- `ADMIT_TIMEOUT` = **15 min**.
- `STOP_GRACE` = **10 s** (SIGTERM, then SIGKILL).
- `RUNAWAY_FACTOR` = **1.5**.
- `BUDGET_MARGIN` = **1.25**.

**Budgets — measured, not guessed.** `tools/memguard_budgets.json` maps each step name to its budget. A budget is the measured **peak RSS of the whole process tree** × `BUDGET_MARGIN`, rounded up to 0.5 GiB, recorded with the measured value, date, and machine.
- An unmeasured step gets **8 GiB** and a loud `UNMEASURED` warning on every run. It must be measured (`memguard measure`) before anyone relies on it.
- Initial step names: `godot_import`, `godot_selftest`, `godot_tests`, `flutter_test`, `sync_e2e`, `demo_import`, `pbf_spike`, `rom_spike`, `flutter_build_ios`.

**Admission** (`memguard run <step> -- <command…>`):
1. **One heavy step at a time** for this project, machine-wide: an exclusive `fcntl.flock` on `~/.cache/tenth_spring/locks/heavy.lock` (override with `TENTH_SPRING_LOCK_DIR`). The kernel releases it automatically if the holder dies.
2. **Wait for room:** wait until **available ≥ budget + FLOOR** and **pressure < 4**. Poll every 2 s, and log every 30 s: `memguard: waiting for memory for <step>: need <X> GiB, have <Y> GiB`.
3. **Give up cleanly:** after `ADMIT_TIMEOUT`, exit **75** with `memguard: not enough free memory for <step> (need <X> GiB, have <Y> GiB) — other programs are using it; close some or try later`. **Never start anyway.**
4. **Nested runs:** the child gets the environment variable `TENTH_SPRING_MEMGUARD_HELD=<step>`. A nested `memguard run` seeing it skips the lock and admission — the parent's budget must cover the whole tree. This prevents self-deadlock (e.g. `test_runner.py` under CI).

**Watchdog** (while the step runs; the child is started in its own process group):

Every 2 s, read available memory, pressure, and the child's **process-tree RSS** (from `ps -A -o pid=,ppid=,rss=`). Stop the whole process group — SIGTERM, then SIGKILL after `STOP_GRACE` — if any of these holds:
- **(a)** pressure is critical (4) on **2 consecutive** polls;
- **(b)** available memory < `FLOOR / 2`;
- **(c)** tree RSS > budget × `RUNAWAY_FACTOR` — the step is using far more than it declared.

On a stop, exit **76** with `memguard: stopped <step> — <cause>; peak <P> GiB`.

**Log:** every run appends a JSON line to `~/.cache/tenth_spring/memguard.log` (outside the repo): step, budget, peak, `waited_ms`, outcome (`ok` / `timeout` / `stopped:<cause>` / `failed:<exit>`).

**Other commands:**
- `memguard doctor` — readings, the cross-check (§1), the budgets table, and the current lock holder's pid.
- `memguard measure <step> -- <command…>` — holds the lock, watches with a generous 2× cap, reports the peak, and writes the budget.

**Agent rules:**
- Never run a heavy command outside `memguard`.
- Never background a heavy job that outlives the session.
- Read `memguard doctor` before a long run.
- If a step exits 75 or 76, report it — don't retry in a loop.

## 3. The game's heavy operations — bounded and pausable

### 3.1 Map-file conversion (the largest risk)
Converting a regional `.osm.pbf` (hundreds of MB to over 1 GB) into the map store (`design_world_generation.md` §3) must peak at **≤ 1 GiB RSS for any region size**:
- **Stream blob by blob.** Read with `FileAccess` (seek + `get_buffer`): a BlobHeader (reject if > **64 KiB**), then a blob (reject if its declared raw size > **32 MiB**) — both are the PBF format's hard limits. **Never** `get_file_as_bytes` on an extract.
- **Bounded parallelism:** at most **4** blocks decoded at once, one per worker thread.
- **Never a Dictionary of all nodes.** Resolving way geometry needs node coordinates. Collect the IDs of nodes referenced by kept ways into a sorted, de-duplicated `PackedInt64Array`, spilling to a temporary SQLite table if it would pass **32 M** IDs. Then keep coordinates **only for those nodes**, as fixed-point (1e-7°) `PackedInt32Array`s found by binary search — or in the temporary table.
- **Batched writes:** at most **10,000** features per transaction.
- **Checkpoint and resume:** an `import_state` row (pass, last blob offset) in the map store lets conversion stop at any block boundary and resume there.
- **Pause, don't die.** Before each block, read `OS.get_memory_info()`.
  - **Pause** if available < **max(1 GiB, 10% of physical)**. The workers finish their current block and idle, and the screen shows `Paused — your computer is low on memory. Map preparation will continue automatically.`
  - **Resume** once available ≥ that floor + **512 MiB** for **10 s** straight.
  - Running low on memory is **never** an error. Only the player can cancel.
- **Pre-check:** start only when available ≥ **2 GiB**; otherwise begin in the paused state.

### 3.2 ROM import
- **Stream from the cartridge file.** Read each archive by its FAT offset (seek + `get_buffer`), never the whole ROM.
- **Decode one sprite at a time**, write it to the cache, and release it.
- **Bounded peak:** the import peaks at ≤ **512 MiB** RSS and follows the same pause rule as §3.1.

### 3.3 While playing
- **Map rendering:** keep only the cells in view plus a 1-cell margin, in an LRU cache of at most **256** decoded cells.
- **Sprites and icons:** through `asset_db`, an LRU of at most **128** battle sprites.
- **SQLite:**
  - the save runs with `PRAGMA cache_size = -65536` (64 MiB); map stores are opened read-only with `-32768` (32 MiB);
  - no `SELECT` without a `WHERE` or `LIMIT` on tables that grow (`visit_log`, `map_cell`, `place_node`, map-store features);
  - results are paged at ≤ **1,000** rows.
- **Target:** the running game stays ≤ **1.5 GiB** RSS at 1080p with 1,000 revealed cells. This is measured in the Phase 9 performance pass.

### 3.4 Phone companion
- **Bounded reads:** outbox reads stay paged (≤ 500 rows — already the case), and GPX replay streams its file.
- **Bounded detection:** the detector keeps only the current dwell window, never the day's fixes.
- **Nothing to clear yet:** there are no large in-memory caches to drop on an iOS memory warning. Keep it that way.

## 4. How these guards are proven

- **Tooling — `tools/test_memguard.py`** (stdlib `unittest`, wired fail-closed into `test_runner.py`), with an injectable fake memory reader and clock:
  1. admits when there is room;
  2. waits, then admits when memory frees up;
  3. times out with exit 75 and the exact message;
  4. a real `sleep` child is stopped when fake pressure turns critical twice (exit 76);
  5. **falsifying, real memory:** a child that allocates ~200 MiB under a 50 MiB budget is stopped as a runaway;
  6. a second process waits for the lock, and the lock frees when its holder is SIGKILLed;
  7. a nested run with `TENTH_SPRING_MEMGUARD_HELD` set doesn't deadlock.
- **Game:** the map-conversion plan's speed spike must report **peak memory** alongside MB/s for both test files. Its unit tests run the converter on the synthetic PBF fixture with a fake `get_memory_info` that drops below the floor mid-run, and assert that it pauses, resumes, and produces an identical map store.

## 5. Files
* `tools/memguard.py`, `tools/memguard_budgets.json`, `tools/test_memguard.py` — the tooling guard.
* `game/world/region_import/` — the streaming converter (§3.1).
* `game/rom/importer.gd` — the streaming ROM import (§3.2).
