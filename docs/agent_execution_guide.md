# Agent Execution Guide — Active Build: Foundation Completion (verified 2026-07-22)

**You are an engineering agent picking up Tenth Spring with zero prior context.** Two builds: a PC game (**Godot 4**, `game/`, canonical world DB) and a thin phone companion (**Flutter**, `companion/`, capture + sync only). The PC holds all gameplay; the phone is never a place to play.

**What is approved:** the three queued items in §2, in that order. **What NOT to touch:** everything in §7 (already delivered), §8 (accepted equivalents), and §9 (intentional decisions).

**Specs are decisions, not suggestions.** Every number, constant, and literal string below is deliberate — implement as written; do not substitute your own values. If a value is genuinely impossible, keep the *intent*, deviate minimally, and note it in the commit body. If the design itself cannot work, **STOP and file it in `docs/ongoing_general_errors.md` with options for the human — do not improvise.**

**Standing constraints (apply to every item):**
- Every change must leave the §1 battery green. That battery is the regression bar.
- Anything touching location capture, battery, or cross-device sync **requires a real-device check**. A simulator or desktop never validates these.
- The two golden invariants (§9) must stay green, always.
- Detailed system behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_foundation.md` (build steps). This guide points at them; it does not restate them.
- One item = one Conventional Commit, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item, not afterwards.

---

## 1. Verified baseline (run this session, 2026-07-22)

These are the current passing numbers. **Do not regress them.**

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **12/12 passed** |
| Game static audit | `python3 game/tests/test_runner.py` (from repo root) | **Lint pass; Golden Invariant 1 guard intact** |
| Game runtime tests | `godot --headless` | ⚠️ **NOT EXECUTED — Godot is not installed in this environment.** `db_test.gd`, `idempotent_sync_test.gd`, `sync_ingest_isolation_test.gd` are verified by reading only. Install Godot before claiming any game-side runtime result. |

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 1 | **D3 — real background capture** (companion) | Phase 0's exit gate is still unmet, and phase discipline says don't deepen Phase 1 first. It is companion-side, so it can proceed in parallel with #2 — and its acceptance needs a multi-hour device soak, so start the clock early. |
| 2 | **F4 — real SQLite store** (game) | Must precede #3: building transport against the in-memory stub means re-plumbing every DB call afterwards. Also converts #3's "transactions" from decorative to real. |
| 3 | **D4 — secure transport** (both) | Depends on #2's real store and accessors. Largest item; do it last so it lands on a stable foundation. |

Deferred (trigger-gated, **do not start**): **F7** — see §6.

---

## 3. Item 1 — D3: real background capture

**What this means for the user:** without this, the phone silently stops scouting the moment the app leaves the screen. The entire premise — "live your life and the map draws itself" — fails quietly.

### The gap
- `companion/lib/capture/os_location_source.dart:47-50` builds a bare `LocationSettings(accuracy: medium, distanceFilter: 25)` — the generic, **foreground-only** settings class. No `AndroidSettings` (no foreground-service config), no `AppleSettings` (no `allowBackgroundLocationUpdates`).
- `companion/lib/capture/os_location_source.dart:23` — `nativeVisits()` returns `null`, so the OS visit-hint path (`location_source.dart:27-40`) is dead on both platforms.
- Platform config is absent: the Android manifest lacks background/foreground-service permissions, and `ios/Runner/Info.plist` lacks `UIBackgroundModes: location`.

Effect: the OS suspends the stream on backgrounding; the ledger stops filling; the Phase 0 exit criterion cannot be met.

### Implementation
1. Replace the generic settings with platform branches:
   - **Android:** `AndroidSettings(accuracy: LocationAccuracy.medium, distanceFilter: 25, intervalDuration: Duration(minutes: 2), foregroundNotificationConfig: ForegroundNotificationConfig(notificationTitle: "Tenth Spring", notificationText: "Scouting your map", enableWakeLock: false))`
   - **iOS:** `AppleSettings(accuracy: LocationAccuracy.medium, distanceFilter: 25, activityType: ActivityType.other, pauseLocationUpdatesAutomatically: true, showBackgroundLocationIndicator: false, allowBackgroundLocationUpdates: true)`
2. Android manifest: add `ACCESS_BACKGROUND_LOCATION` (API 29+), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (API 34+), `POST_NOTIFICATIONS` (API 33+).
3. iOS `Info.plist`: add `UIBackgroundModes` = `location`. The `NSLocationAlwaysAndWhenInUseUsageDescription` copy must match `design_privacy_and_location.md` §3 **verbatim** — that string is the store-review rationale.
4. Staged permission request: foreground first, then background as a **separate** call (required Android 11+). Declining background must leave a working app — keep the manual "scout here" path (`design_privacy_and_location.md` §2).
5. Do **not** raise accuracy above `medium` or drop `distanceFilter` below 25 m. Those two are the battery-budget levers (§A7).
6. If the gate fails after this, escalate to Decision 3 Option A (Transistorsoft) and **record the outcome on Decision 3** — do not silently ship a failing implementation.

### Validation
- **Automated (this one fails against today's code, proving the change landed):** assert `OsLocationSource` constructs `AndroidSettings` with a non-null `foregroundNotificationConfig`, and `AppleSettings` with `allowBackgroundLocationUpdates == true`.
- **Automated:** `flutter analyze` → 0 issues; `flutter test` → still 11/11 plus the new test.
- **Manual device gate (required):** install on a real phone, background the app, carry ≥8 h of normal movement. Assert (a) the ledger gained entries **while backgrounded**, and (b) app battery attribution is **< 3%/day** (iOS Settings → Battery; Android Battery Historian).

### Blast radius (same commit)
`companion/android/app/src/main/AndroidManifest.xml` · `companion/ios/Runner/Info.plist` · `companion/lib/main.dart` (permission flow) · Decision 3 status in `ongoing_general_errors.md`.

---

## 4. Item 2 — F4: real SQLite store

**What this means for the user:** today, closing the game erases the entire map they walked. This is the difference between a demo and a save file.

### The gap
- `game/autoloads/db.gd:8-17` — every table is an in-RAM Godot `Dictionary`. Nothing survives a restart.
- `game/autoloads/db.gd:29-30` — `init_db()` only writes a version string; there is no DDL and no migration runner.
- `game/autoloads/db.gd:35-55` — "transactions" deep-copy four dictionaries and restore them on rollback. That is not durability.
- Result: the §B2 DDL and §B6 migration framework in `implementation_plan_foundation.md` are unrealized.

### Implementation
1. Add a SQLite GDExtension (per Decision 4 tooling: a maintained binding if one exists, else wrap it yourself). **Record which you chose on Decision 4.**
2. Open the DB at `user://tenth_spring.db`. Implement the §B2 DDL exactly — `meta`, `world_clock`, `map_cell`, `place_node`, `visit_log`, `sync_peer`, `player_profile`, `base_state`, `inventory_item`, `osm_cache`. `visit_log` **must** keep `PRIMARY KEY (peer_id, seq)`: that composite key *is* the idempotency guarantee.
3. Implement the §B6 migration runner keyed on `meta.schema_version` — ordered, idempotent, and never destructive to `visit_log` or `map_cell`.
4. Port every existing public method with **unchanged signatures** (`get_map_cell`, `upsert_map_cell`, `get_place_node`, `upsert_place_node`, `is_visit_logged`, `insert_visit_log`, `get_sync_peer`, `update_sync_peer`, `get_schema_version`) so callers don't churn.
5. Replace snapshot transactions with real `BEGIN` / `COMMIT` / `ROLLBACK`.
6. Add public accessors to end direct private-store access: `get_base_state()` and `set_player_tile(x, y)`.
7. Remove the `simulateFailure` production-path test hook (`game/autoloads/sync_server.gd:44` and `:54-56`); drive the rollback test with a real injected DB failure instead.

### Validation
- **Automated — persistence (fails against today's in-memory store, proving the change):** write a `map_cell`, close the DB, reopen it, assert the row is still there.
- **Automated:** schema round-trip — insert one row per table, read back identical.
- **Automated:** migration fixture — open a v0 fixture DB, run migrations, assert `schema_version == 1` and **zero `visit_log` rows lost**.
- **Automated:** `game/tests/idempotent_sync_test.gd` still passes under real transactions (replay ⇒ `appliedCount == 0`; injected failure ⇒ no state persisted).
- **Manual:** run `godot --headless` once and confirm `test_runner.py` reports **executed** runtime tests instead of the "Godot not found" note.

### Blast radius (same commit)
- `game/scripts/relocation_manager.gd:25` — reads `DB._base_state_store` directly → use `DB.get_base_state()`.
- `game/scripts/relocation_manager.gd:71-72` — mutates `DB._player_profile_store` directly → use `DB.set_player_tile()`.
- `game/autoloads/sync_server.gd:44,54-56` — remove `simulateFailure`.
- `game/tests/db_test.gd`, `game/tests/idempotent_sync_test.gd` — update to the new store.

---

## 5. Item 3 — D4: secure transport, both sides

**What this means for the user:** this is the moment the two halves become one product. Until it exists, walking around never reaches the game.

### The gap
- **No `companion/lib/sync/` directory exists** — no pairing, no transport, no mDNS client.
- `game/autoloads/sync_server.gd` is a pure in-process function; `process_batch()` is only ever called directly by tests. No TCP listener, no mDNS advertisement, no encryption anywhere.
- Dependencies are already installed but entirely unused: `multicast_dns`, `cryptography`, `mobile_scanner`, `flutter_secure_storage` in `companion/pubspec.yaml`.
- Result: `design_companion_and_sync.md` §2–3 is unimplemented, and the privacy contract ("exactly one E2E-encrypted hop") is untested.

### Implementation
1. **Wire-compatibility spike FIRST.** Before building the channel, prove Dart `cryptography` and the chosen Godot libsodium binding agree: encrypt on one side, decrypt on the other, against a committed shared test vector. Mismatched primitives here cost days.
2. **Pairing** (`companion/lib/sync/pairing.dart` + Godot equivalent): PC generates an X25519 keypair and renders a QR encoding `{v:1, pcId, pcPubKeyB64, mdnsName}`; phone scans it with `mobile_scanner` and generates its own keypair. Both derive the session key via `HKDF-SHA256(salt = sorted(pcId, phoneId), info = "tenthspring-sync-v1")`. Private keys go to `flutter_secure_storage` / OS keychain — **never** the DB.
3. **Discovery:** PC advertises `_tenthspring._tcp` over mDNS; phone resolves via `multicast_dns`. Provide a manual-IP fallback for networks that block mDNS.
4. **Channel:** TCP + libsodium `crypto_secretstream` (XChaCha20-Poly1305) keyed by the session key. One authenticated chunk per message; reject on any auth-tag failure.
5. **Messages** exactly per `implementation_plan_foundation.md` §B4.3 — `HELLO {peerId, schemaVersion}`, `BATCH {rows[], bodyFix}`, `ACK {lastAppliedSeq}`. Refuse on schema-version mismatch rather than applying across versions.
6. **Companion outbox:** on `ACK`, delete rows with `seq <= lastAppliedSeq`; on failure keep them — the PC's `(peer_id, seq)` key makes re-send safe.
7. Never hand-roll crypto. Standard libsodium primitives only.

### Validation
- **Automated:** crypto round-trip against the committed shared vector, **both directions** (Dart→Godot and Godot→Dart).
- **Automated:** loopback integration — run `companion/test/fixtures/errand_day.gpx` through capture → sync, assert the expected `map_cell` / `place_node` / `visit_log` rows on the PC.
- **Automated — replay is a no-op:** re-send an identical batch; assert `appliedCount == 0` and zero state drift.
- **Automated — mid-batch drop resumes identical:** kill the socket before `ACK`, reconnect, assert final DB state equals a clean single-run state exactly.
- **Automated:** flip one ciphertext byte; assert the message is **rejected**, not silently accepted.
- **Manual device gate (required):** real phone + PC on one Wi-Fi; pair by QR and sync. Capture with Wireshark and assert the payload is **ciphertext only** — no plaintext coordinates, and nothing finer than 3 decimal places anywhere on the wire.

### Blast radius (same commit)
`companion/lib/main.dart` (pairing/sync entry) · `companion/lib/outbox/database.dart` (ack/delete + pairing table) · `game/autoloads/sync_server.gd` (becomes a real listener) · `design_companion_and_sync.md` if the protocol deviates · Decision 4 status.

---

## 6. Deferred — trigger-gated, do NOT start

**F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` `fuzzHome()` snaps to a **300 m** grid (`homeFuzzMeters`), while `game/scripts/relocation_manager.gd:46-47` treats the home cell as a **256 m** `CELL_METERS` cell.
**Trigger:** the first commit that wires safehouse designation. Nothing writes `base_state.home_cell_*` today — it is hardcoded to `0` at `game/autoloads/db.gd:15`. Reconcile to one grid at that moment; touching it earlier is speculative work.

---

## 7. Already delivered — do NOT rework
Phase 0 capture pipeline (`LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, Drift outbox, `GpxReplaySource` + fixtures, scout-ledger UI) · **F1** relocation unit math · **F2** transaction + rollback path · **F3** cell/tile grid unification (256 m / 16 m) · **F5** Godot-headless-aware test runner · **F6** `base_access_meters` stranded threshold · idempotent sync apply · golden-invariant guards.

## 8. Accepted equivalents — do NOT "fix" these back
- `game/scripts/relocation_manager.gd:63-72` implements "nearest-revealed-tile snapping" as *minimal-circle reveal around the spawn cell, then place at the computed tile*, instead of a BFS search for the nearest already-revealed tile. The outcome is equivalent — the survivor always stands on revealed ground. **Accepted.**
- `game/tests/test_runner.py` is a **static lint + capability guard**, deliberately *not* the sync test gate. It is not a substitute for Godot headless runtime tests, and should not be extended into one.

## 9. Intentional decisions — do NOT change
- **Cartography, never cargo** *(golden invariant 1)* — sync ingest writes only `map_cell` / `place_node` / `visit_log` (+ transient `bodyFix`). No inventory path, ever. Guarded by `sync_ingest_isolation_test.gd`.
- **Raw coordinates never persist or transit** *(golden invariant 2)* — full precision exists only in volatile capture memory; everything stored or sent is fuzzed. `companion/lib/capture/fuzz.dart` is the only place raw coordinates appear.
- **Intel, never inventory** — repeat real visits raise `IntelLevel` only.
- **Fast travel = the phone's position at sync time** (a desktop has no GPS); **stranded** away from base; **death drops a recoverable cache**; **map/knowledge always persist**.
- **The phone is never a place to play** — capture + read-only map + sync only.
- **World clock pauses when the game is closed** (except capped colony catch-up). Punishing absence is rejected.
- **Travel time is simulation-authoritative** (15 mph over real distance); on-screen movement is aesthetic.
- **Tile synthesis is deterministic** per `(OSM data, cellSeed)`; the tile cache is regenerable, never source of truth.
- **Stack (Decision 1):** Godot (PC) + Flutter (companion), SQLite both sides, **LAN-only** E2E sync. **Never hand-roll crypto.**
- Values in `game/config/tuning.json` are deliberate balance decisions.

## 10. Where the contracts live (don't duplicate them here)
| Need | Doc |
|---|---|
| Pillars, stack | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Build steps + validation for Phase 0–1 | `docs/implementation_plan_foundation.md` |
| Two-fog pipeline, visits→tiles | `docs/design_world_generation.md` |
| Schemas / models | `docs/design_game_state_and_models.md` |
| Travel, clock, fast-travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync protocol | `docs/design_companion_and_sync.md` |
| Enemies, colonies, landmark bosses | `docs/design_threats_and_colonies.md` |
| Raids, noise, familiarity, death | `docs/design_expeditions_and_survival.md` |
| Loot/POI economy · art & item icons | `docs/design_resources_and_base.md` · `docs/design_art_direction.md` |
| Privacy/location contracts | `docs/design_privacy_and_location.md` |
| Decisions, issues, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md contract it names. Specs are decisions.
2 IMPLEMENT Exactly as written. Honor §9 invariants and the standing constraints.
3 VALIDATE  Run this item's validation, then the full §1 battery.
            RED GATE: do not start the next item on a failing one.
4 BLOCKED?  Spec wrong, impossible, or docs conflict → STOP. File in
            ongoing_general_errors.md with options for the human. Do not improvise.
5 RECORD    Move the item to Resolved with what-was-solved; update any design doc
            whose described behavior changed — in this same commit.
6 COMMIT    One item = one Conventional Commit, WHY in the body.
```

## Definition of Done (this build)
- [x] **D3** — background capture on both platforms; device soak shows ledger filling while backgrounded at **< 3%/day**; Decision 3 outcome recorded.
- [ ] **F4** — SQLite store with §B2 DDL + §B6 migrations; persistence test passes across a restart; private-store accesses replaced with accessors; `simulateFailure` hook removed.
- [ ] **D4** — QR pairing + mDNS + encrypted TCP channel both sides; replay is a no-op; mid-batch drop resumes identical; Wireshark shows ciphertext only.
- [ ] Full §1 battery green, **including Godot headless runtime tests actually executing**.
- [ ] `ongoing_general_errors.md` updated; no open finding left describing already-fixed code.

**When all three are checked: the queue is empty. Do NOT invent work.** The only legitimate triggers for further action are: (a) a new item appears in `ongoing_general_errors.md` with a filled `Your selection:` line, (b) the §1 battery regresses on a fresh checkout, (c) the F7 trigger in §6 fires, or (d) the human assigns something. Otherwise, report that the queue is complete and stop.
