# Agent Execution Guide — Active Build: Phase 1 Hardening (sync correctness fixes) + ROM Spike (verified 2026-10-09, pass 13)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`) that only captures location and syncs.

**The game:** a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — whose overworld is the places the player has physically been.
- **Pokémon content** comes from ROMs **the player supplies**, read on their own machine (the PokeMMO model).
- **Scope:** all **649 Pokémon of Generations 1–5**. **Black/White** supplies all data; **Platinum** optionally supplies Diamond/Pearl-style sprites (Decision 10).
- **No commerce:** no Steam release, no sales.

**Where things stand.** The foundation is built and **executed in CI**:
- background capture on the phone;
- a real SQLite save on the PC (vendored `godot-sqlite` v4.4);
- pinned-TLS pairing and sync between them;
- a cross-language end-to-end sync test.

Pass 13 verified all of it in source and in CI logs. It also found **four behavior bugs and two test blind spots** in that new code (F29–F34). Two of the bugs break core promises:
- the phone can put the player somewhere they have never been (F34);
- a phone that loses its pairing can never pair with the same PC again (F33).

Fixing them is this build. Phase 1 closes when the human runs the real-device gate **after** Items 0–2.

**What is approved for build right now:** the queue in §2, in order. **What NOT to touch:**
- §11 — already delivered;
- §12 — accepted equivalents;
- §13 — intentional decisions.

§10 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string below is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work:** **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, no sprites, no text banks, no stat tables, not even in a test fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, dumped from cartridges they own, through `TENTH_SPRING_ROM_BW` (and optionally `TENTH_SPRING_ROM_PT`). Both point **outside** the repo. (`design_rom_asset_pipeline.md` §8)
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. The local battery fails without it.
3. **Never force-push `main`.** Iterate on a branch and merge or fast-forward once green. Pass 13 found three `sync_e2e` iterations force-pushed over `main`; on a public repo, history rewrites are confusing and they defeat the IP guard's range scan.
4. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`, `-shm`, `.tmp`, and `.jsonbak` siblings;
   - the PC identity folder `user://sync_identity/`.

   Tests use `user://test/…` paths.
5. **Download nothing** except what an item names by exact URL. This build names none; the Godot and Flutter installs in CI are already pinned.
6. **Every change leaves the §1 battery and all three CI workflows green** — that is the regression bar.
7. **Anything touching capture, battery, or cross-device sync requires a real-device check** before Phase 1 is declared closed (§2, HUMAN actions).
8. **The golden invariants (§13) stay green, always.**
9. **Detailed behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
10. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
11. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Game-side and sync claims count as executed only when the CI workflow ran them (`gh run view <id> --log`).

---

## 1. Verified baseline (run this session, 2026-10-09, HEAD `60c6801`, pushed)

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **25 passed, 1 skipped.** The skip is `sync_e2e_test`, which only runs via `tools/sync_e2e.py`. |
| Local game battery | `python3 game/tests/test_runner.py` (repo root) | **Pass:** hook check, IP guard, guard self-tests, F22 static audit, vendored-file SHA-256 check, static lint + F19 SQL rule. Godot runtime tests print `game runtime tests SKIPPED — Godot not installed; CI runs them` (no Godot locally). |
| CI `game_tests` | run `37884027917` | **Executed, green.** Godot 4.3 checksum-verified; harness self-test exits 1; **11/11 expected `PASS` lines**; `storage: SQLite extension` logged. |
| CI `Public-Repo IP Guard` | run `37884028057` | **Green** — range scan (with `-m`), full-tree scan, guard self-tests |
| CI `sync_e2e` | run `37884028074` | **Executed, green.** Flutter 3.44.6: analyze + 25 tests. Cross-language loopback: `E2E_SENT rows 14` → `E2E_STATE visit_log 14, last_applied_seq 14`; replay `appliedCount 0`. The Godot log shows one `mbedtls error: returned -0x6c00` per session, as connections close; treat it as benign unless the device gate shows a session failing. |
| IP guard, adversarial | isolated scratch repo | A file introduced **only inside a merge commit** exits 1. The same script with `-m` removed exits 0, so the flag is what catches it. |
| Falsification branches | CI runs `37854908787`, `37855017689` | Re-introduced F13 → `FAIL db_test`; a stray `zz_test` → rejected as unexpected. The harness can fail. |
| Real-device sync gate | phone + PC on Wi-Fi | ⚠️ **NOT RUN** — human; run it after Items 0–2 |
| D3 device soak | 8 h background carry | ⚠️ **NOT RUN** — human (Decision 5 = A) |

⛔ **Read before trusting any status note or commit message.** The last two builds were genuinely delivered, and still shipped behavior bugs that no test covered: a hardcoded San Francisco fallback location, a re-pair dead end, and an error reported to the player as success. **A green suite proves only what its assertions check.** Read the user-facing path end to end.

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 0 | **F34 — `bodyFix` is only ever a real fix** (PC + phone) | **Highest stakes.** Today one tap of *Report to PC* before the first GPS fix can reveal map in San Francisco, or reset the player to 0, 0 — breaking pillar 1 and fast travel. Touches `process_batch`, which Item 2 also edits; do this first. |
| 1 | **F33 — re-pairing after `unpaired` actually re-pairs** (phone) | A user-facing dead end the device gate would hit as soon as a second phone is tried. Independent of Item 0. |
| 2 | **F32 — storage failures are `ERROR storage`, never "success"** (PC + phone) | Builds on Item 0's `process_batch`. **After this item, ask the human to run the device gate (§2 HUMAN).** |
| 3 | **F31 — a failed legacy import closes the database** (PC) | One-time path for old saves; low frequency, but silent damage when it happens. Isolated to `db.gd`. |
| 4 | **F29 + F30 — close two test blind spots** (runner + guard self-test) | Test-only, so it changes no behavior. Last among the fixes because nothing above depends on it, though it guards standing constraint 4 for every future item. |
| 5 | **Phase 2 — ROM spike + importer implementation plan** | ⛔ **Waits on the human supplying a Black/White dump.** Produces findings, a plan, and a sprite comparison for Decision 10. |

**▶ HUMAN actions:**
- **After Item 2 lands:** run the **real-device sync gate** — the five steps at the end of Item 2's validation (§5). It closes Phase 1.
- **Any time:** the D3 device soak (closes Phase 0).
- **To unblock Item 5:** a Black or White (USA) dump from your own cartridge (`TENTH_SPRING_ROM_BW`), plus Platinum (`TENTH_SPRING_ROM_PT`) if you want the Decision 10 comparison.
- **Decision 10** — sprite style; best decided after Item 5's comparison.

Deferred (trigger-gated, **do not start**): **F7**, **mDNS discovery (F27 d)**, **Black 2/White 2 and non-USA ROMs** — see §9.

---

## 3. Item 0 — F34: `bodyFix` is only ever a real fix

**What this means for the user:** today, tapping *Report to PC* before the phone has a location can teleport them to San Francisco — revealing map there — or to the middle of the ocean at 0, 0. Fast travel must only ever use where their phone really was.

### The gap
- **Phone:** `companion/lib/ui/scout_ledger_screen.dart:187-191` builds `bodyFix` as `"lat": _lastFixLat ?? 37.775, "lon": _lastFixLon ?? -122.419, "tsUtcMs": DateTime.now()...`. That is a hardcoded fallback location, stamped with the **send** time instead of the fix's time. `_lastFixLat/_lastFixLon` (`:35-36`, set at `:101-103`) don't keep the fix's `tsUtcMs`.
- **Phone API:** `ScoutLink.report` (`companion/lib/sync/scout_link.dart:202`) and `SyncTransport.buildBatchPayload` (`companion/lib/sync/transport.dart:16-29`) require a non-null `bodyFix` and always send the key.
- **PC:** `game/autoloads/sync_server.gd:195-199` reads `float(body_fix.get("lat", 0.0))` etc., so a BATCH without `bodyFix` writes **0, 0 at time 0** into `sync_peer.last_body_*`.
- **PC validation:** the dispatcher (`:332-342`) validates `bodyFix` only if present, and never checks `tsUtcMs`.
- **Contract (updated this pass):** `design_companion_and_sync.md` §3 ("`bodyFix` is only ever a real fix"); `implementation_plan_foundation.md` §B4.3 (`bodyFix?` optional) and §B4.4 step 3.

### Implementation
1. **PC dispatcher (`_handle_batch`).** If the frame has a `bodyFix` key, all of these must hold, else `ERROR protocol` and nothing applied:
   - it is a Dictionary;
   - `lat` and `lon` are numeric, in range, and pass `SyncServer.is_fuzzed_coord`;
   - `tsUtcMs` is numeric, integral, and `> 0`.

   A frame **without** the key is valid.
2. **New DB accessor** in `game/autoloads/db.gd`, bound parameters only:
   ```
   update_sync_peer_seq(peer_id: String, last_applied_seq: int) -> void
     INSERT INTO sync_peer (peer_id, last_applied_seq) VALUES (?, ?)
       ON CONFLICT(peer_id) DO UPDATE SET last_applied_seq = MAX(sync_peer.last_applied_seq, excluded.last_applied_seq);
   ```
3. **Make `update_sync_peer` refuse stale fixes.** Change its conflict clause so an **older** fix never overwrites a newer one:
   ```
   ... ON CONFLICT(peer_id) DO UPDATE SET
         last_applied_seq = MAX(sync_peer.last_applied_seq, excluded.last_applied_seq),
         last_body_lat = CASE WHEN excluded.last_body_ts >= COALESCE(sync_peer.last_body_ts, 0) THEN excluded.last_body_lat ELSE sync_peer.last_body_lat END,
         last_body_lon = CASE WHEN excluded.last_body_ts >= COALESCE(sync_peer.last_body_ts, 0) THEN excluded.last_body_lon ELSE sync_peer.last_body_lon END,
         last_body_ts  = MAX(COALESCE(sync_peer.last_body_ts, 0), excluded.last_body_ts);
   ```
4. **`process_batch`.** If `batch_data` has a non-empty `bodyFix`, call `update_sync_peer(peer_id, max_seq, lat, lon, ts)`; otherwise call `update_sync_peer_seq(peer_id, max_seq)`. **Delete** the `get(..., 0.0)` defaults for body fields.
5. **Phone — remember the real fix.** In `scout_ledger_screen.dart`, replace `_lastFixLat`/`_lastFixLon` with one nullable field holding `{lat, lon, tsUtcMs}`: the **fuzzed** lat/lon from `fuzzPoint(fix.lat, fix.lon)`, and `fix.tsUtcMs` (`companion/lib/capture/location_source.dart:11`).
6. **Phone — never invent one.** `_reportToPc()` passes `bodyFix: _lastFix == null ? null : {"lat":…, "lon":…, "tsUtcMs": _lastFix.tsUtcMs}`. **Delete both literals** `37.775` and `-122.419` from `companion/lib/`.
7. **Phone API.** `ScoutLink.report({required AppDatabase db, Map<String, dynamic>? bodyFix})`. `buildBatchPayload(rows, Map<String, dynamic>? bodyFix)` adds the `"bodyFix"` key **only** when non-null.

### Validation
- **Falsifying (Godot, `sync_session_test`):**
  1. Pair and HELLO.
  2. BATCH with `bodyFix {lat 37.776, lon -122.420, tsUtcMs 2000}`.
  3. BATCH (new seq) **without** `bodyFix`.
  4. `get_sync_peer` still shows `37.776 / -122.420 / 2000`.

  **Today step 4 shows 0 / 0 / 0.**
- **Falsifying — stale fix:** a later BATCH with `bodyFix tsUtcMs 1000` leaves the stored position at the ts-2000 values.
- **Protocol:** a `bodyFix` with lat `37.7761` → `ERROR protocol`; a `bodyFix` without `tsUtcMs` → `ERROR protocol`.
- **Dart:**
  - `buildBatchPayload(rows, null)` has no `bodyFix` key.
  - `report(bodyFix: null)` against the existing fake server sends a BATCH whose captured frame lacks `bodyFix`.
- **Static:** `grep -rn "37.775\|-122.419" companion/lib` returns nothing.
- **All three CI workflows green.** The e2e test still sends a real `bodyFix`; keep it.

### Blast radius (same commit)
- **PC:** `game/autoloads/sync_server.gd` (`_handle_batch`, `process_batch`), `game/autoloads/db.gd`, `game/tests/sync_session_test.gd`.
- **Phone:** `companion/lib/ui/scout_ledger_screen.dart`, `companion/lib/sync/scout_link.dart`, `companion/lib/sync/transport.dart`, `companion/test/sync_test.dart`.
- **Tracking:** F34 → Resolved. The contracts are already updated.

---

## 4. Item 1 — F33: re-pairing after `unpaired` actually re-pairs

**What this means for the user:** if they ever pair a second phone (or the PC forgets this one), the app tells them to scan the code again — and today that scan says "Scout recruited successfully!" while leaving them permanently unable to report.

### The gap
- **The short-circuit ignores lost tokens.** `companion/lib/sync/scout_link.dart:114-118`: `pair()` returns `PairOk` after only refreshing addresses whenever the stored `pcId` and `fp` match the QR — even if the PC no longer accepts this phone.
- **The phone keeps a dead token.** `report()` (`:256-261`, `:292-297`) returns `ReportUnpaired` but keeps the dead `deviceToken`, so `PairingStore.isPaired()` stays true and the UI keeps offering *Report to PC*.
- **Contract (updated this pass):** `implementation_plan_foundation.md` §B3 step 3; `design_companion_and_sync.md` §2.

### Implementation
1. **`PairingStore.clearDeviceToken()`** — deletes **only** `pairing.deviceToken`. `pcId`, `fp`, `addrs`, `port`, `phoneId`, and `lastGoodAddr` stay.
2. **`report()`:** whenever the PC answers `ERROR` with `code == "unpaired"` (to HELLO **or** BATCH), call `store.clearDeviceToken()` before returning `ReportUnpaired`.
3. **`pair()`:** short-circuit only if `storedPcId == qr.pcId && storedFp == qr.fp && (await store.getDeviceToken()) != null`. Otherwise run the full PAIR path, reusing the stored `phoneId`.
4. **UI:** after `ReportUnpaired`, the ledger shows *Pair with your PC* instead of *Report to PC* — it already keys off `isPaired()`, which now turns false.

### Validation
- **Falsifying (Dart):** store `pcId`/`fp`/`addrs`/`phoneId` with **no** `deviceToken`, then `pair(sameQr)` against a fake PAIR server. The server receives a frame with `type == "PAIR"`, and the new token is stored on `PAIR_OK`. **Today no connection is made.**
- **Dart:** `report()` receiving `ERROR unpaired` leaves `getDeviceToken() == null`, with `phoneId`, `pcId`, and `fp` unchanged and the outbox untouched.
- **Dart:** with a token present, `pair(sameQr)` makes **no** connection (the fake server records zero accepts).
- **Godot (`sync_session_test`), driving the dispatcher:**
  1. Phone A pairs and gets `HELLO_OK`.
  2. Phone B pairs with a fresh code.
  3. A's HELLO → `ERROR unpaired`.
  4. A pairs again with a new code → `PAIR_OK`.
  5. A's HELLO → `HELLO_OK`, and A's earlier `visit_log` rows are still present.

### Blast radius (same commit)
`companion/lib/sync/pairing.dart`, `companion/lib/sync/scout_link.dart`, `companion/test/sync_test.dart`, `game/tests/sync_session_test.gd` · F33 → Resolved.

---

## 5. Item 2 — F32: storage failures are `ERROR storage`, never "success"

**What this means for the user:** if the PC can't save their scouting (disk full, database error), the phone must say so — today it says "Delivered 12 scout reports to PC." (Nothing is lost: the phone keeps the rows. But the player is misinformed.)

### The gap
- **BATCH:** `game/autoloads/sync_server.gd:345-347` stamps `"type":"ACK"` onto whatever `process_batch` returned, including `{"status":"error"}`.
  - On the phone, `handleAckResponse` (`companion/lib/sync/transport.dart`) returns 0 for a non-`ack` status.
  - `report()` then breaks its loop and returns **`ReportOk`** (`scout_link.dart:305-318`).
- **Transaction start:** `process_batch` (`sync_server.gd:125`) ignores `DB.begin_transaction()`'s return value.
- **PAIR:** `_handle_pair` (`:251-253`) ignores the results of `set_peer_token_hash` and `clear_other_peer_tokens`, so it can answer `PAIR_OK` with no token saved. It also **consumes the pairing code before validating** `phoneId`/`deviceToken` (`:239-249`), so a malformed frame burns a valid code.
- **Contract (updated this pass):** the new code `storage` in §B4.3's ERROR list — "ACK only on success."

### Implementation
1. **`process_batch`:** if `DB.begin_transaction()` returns false, return `{"status": "error", "message": "storage error"}` immediately.
2. **`_handle_batch`:** if `result.get("status") != "ack"`, return `{"type": "ERROR", "code": "storage"}`. The session closes, as for any ERROR. Only an `ack` result gets `"type": "ACK"`.
3. **`_handle_pair`, in this order:**
   1. **Validate first, without consuming the code:** `phoneId` is 32 lowercase hex chars, and `deviceToken` base64-decodes to **exactly 32 bytes**. Otherwise → `ERROR protocol`.
   2. **Consume:** `pairing_codes.consume(...)`; on false → `ERROR bad_pair_code`.
   3. **Save the token in one transaction:** `DB.begin_transaction()` → `set_peer_token_hash` → `clear_other_peer_tokens` → `DB.commit_transaction()`. Any `false` → `DB.rollback_transaction()` and `ERROR storage`.
   4. **Only then** emit `peer_paired` and reply `PAIR_OK`.
4. **Phone:**
   - Add result types `ReportPcStorageError` and `PairPcStorageError`.
   - `report()` maps `ERROR storage` to `ReportPcStorageError`; `pair()` maps it to `PairPcStorageError`.
   - **Defensive:** if an `ACK` arrives whose `status != "ack"`, return `ReportProtocolError('ACK without ack status')` — never `ReportOk`.
5. **Copy (scout vocabulary):**
   - **Report:** `Your PC couldn't file this scout report — nothing was lost. Try again in a moment.`
   - **Pair:** `Your PC couldn't save the pairing — refresh the code on your PC and try again.`

### Validation
- **Falsifying (Godot):** fault injection without production hooks — pair and HELLO, then `DB.close()`, then dispatch a valid BATCH. Expect `{"type":"ERROR","code":"storage"}`. **Today the result is `{"type":"ACK","status":"error",…}`.** Re-open the DB with `init_db()` afterwards so later tests are unaffected.
- **Godot:** a PAIR with a 31-byte token → `ERROR protocol`, and the **same** code still pairs successfully afterwards (not consumed). A PAIR with the DB closed → `ERROR storage`.
- **Falsifying (Dart):** a fake server answers BATCH with `ERROR storage` → `report()` returns `ReportPcStorageError`, and the outbox row count is unchanged. **Today it returns `ReportOk`.** An `ACK` with `status: "error"` → `ReportProtocolError`.
- **Then the HUMAN device gate** (closes Phase 1):
  1. **Pair and report:** real phone + PC on one Wi-Fi network. Pair by QR — this also proves a real phone can scan the PC's QR. Walk an errand, then *Report to PC*; the rows appear on the PC.
  2. **Wireshark:** filter `tcp.port == 7350`. The capture shows only TLS records, and searching it for the home's 3-decimal latitude finds nothing.
  3. **iOS:** the local-network prompt appears on the first report.
  4. **Address change:** renew the PC's DHCP lease → *Report to PC* shows the unreachable message. Re-scan → the next report succeeds **without** re-pairing.
  5. **Second phone:** pair a second phone → the first phone's next report shows the unpaired message. Re-scanning on the first phone pairs it again (Item 1).

### Blast radius (same commit)
`game/autoloads/sync_server.gd`, `game/tests/sync_session_test.gd`, `companion/lib/sync/scout_link.dart`, `companion/lib/ui/scout_ledger_screen.dart`, `companion/lib/ui/pairing_screen.dart`, `companion/test/sync_test.dart` · F32 → Resolved.

---

## 6. Item 3 — F31: a failed legacy import closes the database

**What this means for the user:** a player upgrading from an old save whose import fails must not quietly start playing in an empty world while their real map sits in a backup file the game will then never be able to import.

### The gap
In `game/autoloads/db.gd`:
- **The database stays open after a failed import.** On a count mismatch, `_run_legacy_import` (`:343-346`) rolls back and prints `storage: UNAVAILABLE — legacy import mismatch`, but **leaves `_db` open**. Syncs then write into an empty world.
- **The count check compares the wrong totals.** It compares whole-table counts (`:328-341`), so once any row has been written, every later retry mismatches permanently.
- **Unchecked statements:** none of the import's `_q` calls (`:241-316`) check their result, so a failed `world_clock`, `player_profile`, or `base_state` update is invisible to the count check.
- **Misleading error text:** `_q` reports `"SQLite extension not available"` for a closed handle (`:73`) — the `ERROR` line that appears in every CI log.

### Implementation
1. **Precondition.** Before importing, if `visit_log` or `map_cell` already holds any row:
   - print `storage: UNAVAILABLE — legacy import blocked: database already has rows`;
   - `push_error` the same text;
   - `close()` and return.

   A failed import closes the database (step 3), so this can only happen if something else wrote first. Refusing protects the backup.
2. **Check every statement.** Every `_q` inside the import is checked. The first `false` → rollback → failure path (step 3).
3. **One failure path, used for a failed statement and for a count mismatch:**
   - `rollback_transaction()`;
   - print `storage: UNAVAILABLE — legacy import failed: <reason>` (reason = the statement's `last_error` or `count mismatch <table> expected <n> got <m>`);
   - `push_error` the same text;
   - `close()`. Nothing writes for the rest of the session. The backup files are untouched, and the next boot retries.
4. **Unreadable backups.** Keep the current behavior when **both** the backup and its `.tmp` are unparseable (skip, keep the files), but print exactly `storage: legacy save unreadable — kept at <path>`.
5. **Fix the closed-handle message.** In `_q`, when `_db == null`, set `last_error = "storage: database not open"`.

### Validation (Godot, `db_legacy_import_test`)
- **Falsifying:** write a fixture variant with two `visit_log` entries under different keys but the **same** `peer_id` + `seq`. After `DB.init_db()`:
  - `DB._db == null`;
  - `DB.execute_query("SELECT 1;")` returns false;
  - the `.jsonbak` is byte-identical to the variant;
  - an **independent** `SQLite` connection shows no `legacy_import` row in `meta`.

  **Today `_db` is still open.**
- **Precondition:** a database that already has a `map_cell` row, plus a `.jsonbak` and no `legacy_import` row → `init_db()` closes the database, and the row count is unchanged.
- **Happy path:** the existing import test still passes unchanged.
- **CI log:** the `game_tests` log no longer contains `SQLite extension not available`.

### Blast radius (same commit)
`game/autoloads/db.gd`, `game/tests/db_legacy_import_test.gd`, a new fixture variant under `game/tests/fixtures/` · `design_game_state_and_models.md` §0 (already updated this pass — keep it true) · F31 → Resolved.

---

## 7. Item 4 — F29 + F30: close two test blind spots

**What this means for the user:** two safety nets that looked like they worked don't. One protects their real save from the test suite; the other protects the public repo from a ROM slipped in through a merge.

### The gap
- **F29 — the real-save check starts too late.** `game/tests/test_main.gd` snapshots the protected files in its own `_ready()`, which runs **after** the autoloads.
  - **Evidence:** scratch run `37856055127` — `DB._ready()` opened the real save with SQLite live — still printed `PASS real_save_untouched`.
  - **Today it holds only because** `DB._ready()`/`SyncServer._ready()` are `pass` (`game/autoloads/db.gd:35-36`, `sync_server.gd:22-23`).
- **F30 — the merge self-test can't fail.** `tools/test_check_no_nintendo_assets.py::test_range_merge_introducing_rom` adds `bad.bin` in an ordinary feature commit that is itself inside the scanned range, so it passes with or without `-m`. An "evil merge" — a file that exists only in the merge commit — has no test.

### Implementation
1. **F29 — runner-level snapshot**, in `game/tests/test_runner.py`, outside Godot.
   - **Compute Godot's user-data directory** for project name `Tenth Spring`:
     - **Linux:** `$XDG_DATA_HOME` (default `~/.local/share`) + `/godot/app_userdata/Tenth Spring`;
     - **macOS:** `~/Library/Application Support/Godot/app_userdata/Tenth Spring`;
     - **Windows:** `%APPDATA%\Godot\app_userdata\Tenth Spring`.
   - **Protected files** (relative to that directory): `tenth_spring.db`, `tenth_spring.db-wal`, `tenth_spring.db-shm`, `tenth_spring.db.tmp`, `tenth_spring.db.jsonbak`, `sync_identity/pc.key`, `sync_identity/pc.crt`, `sync_identity/pc_id.txt`.
   - **Snapshot** existence + SHA-256 of each **before** the first Godot invocation (the self-test run), and compare **after** the main run.
   - **Any difference** → print `[REAL SAVE CHECK FAIL] <file> changed during the test run` and exit 1.
   - **In CI** (`CI == "true"`), additionally fail if any protected file **exists** after the run; a fresh runner has none.
   - **Vacuity guard:** after the run, assert `<user dir>/test/` exists. The tests create `user://test/`, so this proves the computed path really is Godot's user directory. If it's missing, print `[REAL SAVE CHECK FAIL] computed Godot user dir is wrong: <path>` and exit 1.
   - Keep the in-process `real_save_untouched` as well.
2. **F30 — evil-merge tests** in `tools/test_check_no_nintendo_assets.py`:
   - **`test_range_evil_merge_rom`:**
     1. In a throwaway repo: base commit → branch `feat` adds `f.txt` → `main` adds `m.txt`.
     2. `git merge --no-ff --no-commit feat`.
     3. Stage `evil.bin` = 12 zero bytes + `CPUE`.
     4. Commit the merge.
     5. Assert `--range M^1..M` exits **1** and names `evil.bin`.
   - **`test_evil_merge_requires_m_flag`:**
     1. Copy the guard to a temp file with every `"-m", ` removed.
     2. Run the same scenario against the copy.
     3. Assert exit **0**.

     This proves the first test depends on `-m` — if someone deletes the flag, `test_range_evil_merge_rom` fails.
   - Keep the existing merge test.

### Validation
- **Falsifying (F29):** on a scratch branch, change `DB._ready()` back to `init_db()`. `game_tests` must go **red** with `[REAL SAVE CHECK FAIL]`. Today the equivalent run (`37856055127`) passed this check. Delete the branch; never merge it.
- **Vacuity guard:** the `game_tests` log shows the computed user directory and that `test/` exists in it.
- **Falsifying (F30):** both new self-tests pass, and `test_evil_merge_requires_m_flag` proves the dependency.

### Blast radius (same commit)
`game/tests/test_runner.py`, `tools/test_check_no_nintendo_assets.py` · F29, F30 → Resolved.

---

## 8. Item 5 — Phase 2: ROM spike + importer implementation plan

**⛔ Waits on the human supplying a Pokémon Black or White (USA) dump made from their own cartridge** (`TENTH_SPRING_ROM_BW`). A Platinum (USA) dump (`TENTH_SPRING_ROM_PT`) is optional; it enables the Decision 10 comparison. The IP guard fixes it depends on (F24, F28) are delivered. **Produces findings, a plan, and a comparison image for review. It does not build the production importer.**

**What this means for the user:** the moment the game can show its first Pokémon, and the evidence the human needs to pick a sprite style. Every Pokémon-facing system depends on it.

### The gap
- No importer exists, so the game can't display a single Pokémon.
- The riskiest unknowns are the **verify** markers in `design_rom_asset_pipeline.md` §4–5:
  - Gen 5 sprite cell assembly and the per-species layout in `a/0/0/4`;
  - LZ77 vs LZ11;
  - Gen 5 record sizes and offsets;
  - the Gen 5 text key schedule and which bank holds which names;
  - the item-icon archive;
  - and, for Platinum, the sprite decryption rule.

### Implementation
1. **Preconditions.**
   - `TENTH_SPRING_ROM_BW` is set, the file exists, and `os.path.realpath` of it is **not** inside the repo. Same for `TENTH_SPRING_ROM_PT` if set.
   - If any check fails, STOP and report. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib**, under `tools/rom_spike/`, run with `python3 -I`. The ROM exists only on the human's machine, and Godot isn't installed there; the production importer will be GDScript, so record every rule language-neutrally.
   - **Output** goes to `~/.tenth_spring_rom_spike/` (outside the repo).
   - **PNGs** are written with `zlib` + `struct` — no third-party packages.
   - **The code must embed no bytes, names, or tables taken from a ROM.** Types are compared as numeric ids (Normal 0 … Ghost 7 … Fire 9, Water 10 … Dragon 15, Dark 16).
3. **Header.** Assert the game code against `design_rom_asset_pipeline.md` §2. Compute the SHA-1 and compare it with the No-Intro DAT entry for that title. Record the hash **and the DAT version/source** in the design doc; never guess a hash.
4. **Parse FNT/FAT.** Locate every §5 archive and record actual file counts. Expected for Black: `a/0/1/6` 669, `a/0/1/8` 668, `a/0/1/9` 668, `a/0/2/1` 560, `a/0/2/4` 627, `a/0/0/2` 288, `a/0/0/4` 14,285.
5. **Black/White data.**
   - Decode the personal records for #94, #442, #487, #593, #609, and #623. Record the record size and the field offsets you confirmed.
   - Count species 1–649 and moves (expect 559).
   - Find the text banks holding species, move, item, and ability names; decode #1, #487, and #609.
   - Locate the item-icon archive.
6. **Black/White sprites.**
   - Establish the per-species file layout in `a/0/0/4`, and the compression of each file type.
   - Assemble the **first frame** of the front sprite for **#609 Chandelure** and **#94 Gengar** from NCGR + NCER (+ NCLR, normal and shiny), on a 96×96 canvas.
   - Record the exact assembly rule.
7. **Platinum sprites** (only if `TENTH_SPRING_ROM_PT` is set): decode the front sprites for **#487 Giratina** and **#94 Gengar**, and record the exact decryption rule — seed source and iteration direction — citing `pret/pokeplatinum`.
8. **Comparison image for Decision 10** (only if both ROMs are present):
   - Render #94, #200, #355, and #487 side by side: Platinum style, then Black/White style, at 2× integer scale.
   - Save it to `~/.tenth_spring_rom_spike/decision10_comparison.png`.
   - Tell the human the path. **Never commit it.**
9. **Update the design doc.** Replace every **verify** marker in `design_rom_asset_pipeline.md` §4–5 with the confirmed rule, citing the reference you checked or the experiment. Keep the "never in the repo" columns intact.
10. **Write `docs/implementation_plan_rom_importer.md`** at the depth of `implementation_plan_foundation.md`. Cover:
    - the GDScript modules of design §10;
    - each format rule;
    - the per-ROM resumable `rom_cache.tmp` → rename write;
    - the §7 validation suite;
    - the `asset_db` API, including the Decision 10 switch;
    - the test strategy — ROM tests run only when the env vars are set; in CI they are skipped with an explicit message, never faked.
11. **PAUSE for human review**, and Decision 10. No production importer until the plan is approved.

### Validation
- **Counts:** archive file counts match §5, or the table is corrected with evidence.
- **Types:** match design §7 for all six validation species.
- **Falsifies a wrong decode:** each decoded sprite has ≤ 16 distinct colours per palette and per-pixel variance above a threshold that random "static" cannot pass. Show the threshold failing on a deliberately wrong decode — for example, XOR with the wrong seed.
- **Names:** decode to non-empty strings with no unmapped code units.
- **Nothing leaked:** after the spike, `git status` shows only `tools/rom_spike/*.py` and doc changes — no ROM, PNG, or cache — and the guard exits 0.

### Blast radius (same commit)
`tools/rom_spike/` · `docs/design_rom_asset_pipeline.md` §2, §4–5, §7 · new `docs/implementation_plan_rom_importer.md` · Decision 10 (add the comparison path to its block) · Decision 9/12 status.

---

---

## 9. Deferred — trigger-gated, do NOT start
- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; `game/scripts/relocation_manager.gd:46-47` treats home as a **256 m** cell. **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding).
- **mDNS auto-discovery (F27 d).** v1 finds the PC by remembered address plus QR re-scan.
  - Doing this properly needs two things: a PC-side mDNS responder (Godot has none), and native Bonjour/NSD browsing on the phone (the `nsd` package, not raw multicast, which needs Apple's restricted entitlement on iPhones).
  - **Trigger:** the human reports that re-scanning after an address change is a real nuisance in play.
- **Black 2/White 2 and non-USA ROMs.** **Trigger:** a human request.
- **Session-start relocation (§B5) on game launch.** `relocation_manager.gd` exists, but the main scene doesn't call it yet. **Trigger:** Phase 4 (travel & fast travel). It is not part of Phase 1's exit criterion.

---

## 10. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward, write its `implementation_plan_<phase>.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9, because every Pokémon-facing system reads through `asset_db`.

---

## 11. Already delivered — do NOT rework
- **Phase 0 capture pipeline:** the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, and the scout-ledger UI. D3 background-capture code is done; its device soak is pending.
- **Early fixes:** F1, F2, F3, F5, F6, F8, F9, F11, F13, F17, F18, F21, F22.
- **Pass 12 build (verified pass 13 — M12–M15 in the tracking doc):**
  - **Item 0 / F25:** scene-based Godot test harness (`test_main.tscn`) with discovery, the `EXPECTED` list, a harness self-test, and the `game_tests` CI workflow (Godot 4.3, checksum-verified).
  - **Item 1 / F24, F28:** guard `-m` merge scanning, tip-tree scan, fail-closed git errors, force-push fallback, region-agnostic Gen 4–5 prefixes, and the `core.hooksPath` check.
  - **Item 2 / D7, F4, F10, F16, F19, F20, F23, F26:**
    - vendored `godot-sqlite` v4.4 (desktop only, `VENDORED.sha256` checked);
    - the real SQLite engine — WAL, `synchronous=FULL`, bound parameters only, MAX-semantics upserts;
    - the corrected nine-table v1 DDL;
    - the migration runner and the legacy JSON import;
    - inert autoload `_ready()`, with boot in `game/scenes/main.gd`;
    - the F19 static rule.
  - **Item 3 / D11, F12, F14, F15, F27 a–c:**
    - **PC:** `PcIdentity` (RSA-2048 self-signed certificate + DER fingerprint), `PairingCodes`, `FrameCodec`, the Nayuki-ported `QrCode`, the TLS session state machine, and the pairing screen;
    - **Phone:** `QrPayloadV2`, `PairingStore`, `ScoutLink` (pinned TLS, pair, report), and the frame codec; the old crypto and `multicast_dns` removed; Info.plist/Android permissions added;
    - **CI:** the `sync_e2e` workflow (Godot + Flutter loopback, with replay).

## 12. Accepted equivalents — do NOT "fix" these back
- **`get_blob_head()` default mode** falls back from `HEAD:path` to the index (`:path`), so files staged but not yet committed are still checked. Correct.
- **The IP guard's path rule** also blocks any `roms/` path component — broader than spec; keep it.
- **`relocation_manager.gd:63-72`** "nearest-revealed-tile snapping", done as a minimal-circle reveal plus placement — the same guarantee as BFS.
- **`os_location_source.dart:25`** — `nativeVisits()` returns `null`; native visits are an optional hint.
- **`test_f22_save_isolation.py`** stays as a fast static pre-check; the executed `real_save_untouched` and Item 4's runner check are the proof.
- **The legacy import uses the same `ON CONFLICT` upserts** as live writes, instead of plain `INSERT`s. Equivalent on an empty database; keep it.
- **`SyncServer.configure_identity()` and `create_dispatcher()`** are dependency-injection seams that tests use to drive the dispatcher without sockets. They read no live request data, so they are not test hooks in the production path.
- **The dispatcher accepts an integral float `seq`.** Godot's JSON parser returns all numbers as floats; requiring `TYPE_INT` would reject every real frame.
- **`main.tscn` instances the pairing screen directly**, so it is visible at launch. Acceptable until the game has a menu (Phase 9); don't build a menu for it now.
- **QR codes use ECC level M**, exactly as specified; the payload fits comfortably.

## 13. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever** (standing constraint 1). Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache, through `asset_db` only. **The phone companion never contains Nintendo assets or names.**
- **Roster and rules** (Decision 12):
  - **649 species, Gen 1–5.** Black/White is the single data source; Platinum supplies only sprites, and only if Decision 10 says so.
  - **Gen IV formulas over Gen V data** — 17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5.
  - No hidden abilities in v1. Gen 6+ is permanently out of scope.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell`, `place_node`, and `visit_log` (+ the body position). **When bag, party, PC box, or Pokémon tables are added, extend the isolation scan's forbidden tokens** in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist, and the PC refuses any coordinate finer than 3 decimals, `bodyFix` included.
- **`bodyFix` is only ever a real, fuzzed, fix-timestamped observation** — never a default, never the send time. If there is no fix, omit it (F34).
- **Sync security** (Decision 11):
  - **TLS with a pinned self-signed certificate plus a device token.** The phone uses `withTrustedRoots: false` and re-checks the peer certificate after connecting. **Never hand-roll crypto**; don't reintroduce libsodium or an app-level AEAD.
  - **One paired phone per PC.** Re-pairing never deletes history. An `unpaired` answer discards the phone's token, so the next scan really re-pairs (F33).
  - **ACK means success.** Every failure is an `ERROR` frame with a code (F32).
- **Storage** (Decisions 6–7):
  - **SQLite only** — no second persistence path. **Bound parameters only.**
  - **The v1 DDL is frozen**; every change is a §B6 migration.
  - **Any storage failure at boot closes the database for the session** ("UNAVAILABLE"); it never silently degrades.
- **Pillar rules:**
  - Fast travel = the phone's position at sync time.
  - **Stranded:** the PC box is reachable only within `baseAccessMeters`.
  - **Healing only at home.** **Blackout drops the bag, never Pokémon.**
  - The map and Pokédex always persist.
- **The phone is never a place to play.** **The world clock pauses when the game is closed** (except capped haunting catch-up). **Tile synthesis is deterministic.**
- **Stack:** Godot 4.3 (PC) + Flutter (companion). No Steam, no monetization. Discovery by address; mDNS deferred (§9).
- **Deliberate values:** the capture settings (accuracy `medium`, 25 m, 2 min) are battery decisions, and the `tuning.json` values are balance decisions.

## 14. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, distribution | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Build steps for Phases 0–1, the v1 DDL, the TLS sync protocol, the **Godot test harness contract** | `docs/implementation_plan_foundation.md` |
| ROMs (Black/White + optional Platinum), formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
| Stats, types, damage, catching, party, PC, blackout | `docs/design_creatures_and_battles.md` |
| Spawn zones, ghost share, levels, haunted zones, legendaries | `docs/design_encounters_and_haunted_zones.md` |
| Exploring sites, familiarity, healing scarcity | `docs/design_expeditions_and_survival.md` |
| Items by place, bag, home safehouse | `docs/design_resources_and_base.md` |
| Visits → tiles, tall grass, landmarks | `docs/design_world_generation.md` |
| Schemas + storage backends | `docs/design_game_state_and_models.md` |
| Travel, clock, fast travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync | `docs/design_companion_and_sync.md` |
| Original vs. ROM-sourced art | `docs/design_art_direction.md` |
| Privacy | `docs/design_privacy_and_location.md` |
| Decisions, findings, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md / implementation_plan_*.md sections it names.
            Specs are decisions.
2 PLAN      Building a phase with no implementation_plan_*.md at build depth? Write one
            FIRST and PAUSE for human review. Applies to every phase from 2 on.
3 IMPLEMENT Exactly as written, on a branch. Honor §13 and the standing constraints —
            above all: no Nintendo content in the repo; no test touches the real save or
            identity; never force-push main.
4 VALIDATE  This item's validation, then the full §1 battery, then confirm all three CI
            workflows on GitHub (`gh run view <id> --log`). Report what actually ran:
            "source-verified", "statically checked", and "executed" are different claims.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, or you'd need a ROM you don't have →
            STOP. File in ongoing_general_errors.md with options. Do not improvise.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design
            doc whose behavior changed — in the same commit.
7 COMMIT    One Conventional Commit per item, WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 0 (F34)** — a BATCH without `bodyFix` leaves the stored body position unchanged; a stale fix can't overwrite a newer one; no location literals remain in `companion/lib`; executed in CI.
- [x] **Item 1 (F33)** — after `unpaired`, scanning the same PC's QR sends a real PAIR and the phone reports again; executed in CI.
- [x] **Item 2 (F32)** — a storage failure reaches the phone as `ERROR storage` → `ReportPcStorageError`; a malformed PAIR doesn't burn the code; executed in CI.
- [ ] **HUMAN: real-device sync gate passes** (Item 2 validation, steps 1–5). **Closes Phase 1.**
- [x] **Item 3 (F31)** — a failed legacy import leaves `_db == null` with the backup intact; executed in CI.
- [x] **Item 4 (F29 + F30)** — a re-added boot-time `init_db()` turns CI red via the runner check; the evil-merge self-tests pass and prove their dependency on `-m`.
- [ ] **HUMAN: D3 device soak run** (Decision 5 = A). **Closes Phase 0.**
- [ ] **A Black/White dump supplied**, then **Item 5** — the verify markers are resolved, `implementation_plan_rom_importer.md` is written, the comparison is shown (if Platinum was supplied), and the work is **paused for review and Decision 10**.
- [x] The full §1 battery and all three CI workflows are green.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate step is building the ROM importer from the *approved* plan, then Phase 3. Other legitimate triggers:
- a new item in `ongoing_general_errors.md` with a filled `Your selection:`;
- the §1 battery or any CI workflow regressing;
- a §9 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
