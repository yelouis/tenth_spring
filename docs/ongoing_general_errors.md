# Ongoing General Errors & Engineering History

## Overview
This document tracks key engineering insights, regression-risk pitfalls, open decisions, and historical system updates for Tenth Spring. Major architectural design layers are documented in dedicated system design files under `docs/`. Format mirrors Gaslight's conventions: issues are numbered, decisions get options + a `Your selection:` line, and resolved items move to the Resolved section with what-was-solved.

---

## 🟠 Open Decisions

_These two implementation sub-decisions surfaced while writing `implementation_plan_foundation.md`. Neither blocks starting Phase 0 prototyping — both can be resolved against the `LocationSource` / crypto interfaces once a spike is done._

### Decision 3: Companion background-geolocation implementation (Phase 0)
How the phone captures location in the background (significant-location-change + visits) within the <3%/day battery budget.
- **Option A**: `flutter_background_geolocation` (Transistorsoft) — battle-tested SLC + visit + motion + geofencing + persistence + battery management out of the box. Cost: paid license for Android *release* builds; large dependency.
- **Option B**: Thin custom platform channels — iOS `CLVisit` + significant-location-change; Android foreground service + FusedLocationProvider (balanced priority) + our own dwell detection. Cost: we own all battery/edge-case tuning; more native code to test.
- Recommendation: prototype B behind the `LocationSource` interface (`implementation_plan_foundation.md` §A2); adopt A only if B misses the battery/reliability target.
- **Your selection (July 21): Option B first (free/custom), fall back to A (Transistorsoft) if the Phase 0 battery/reliability gate fails.** Provisional — revisit after the Phase 0 device spike; the `LocationSource` seam keeps the swap cheap.
- **Status (verified July 22): REALIZED (Option B).** `OsLocationSource` is implemented behind `LocationSource` with `AndroidSettings` (Foreground Service notification, 2-min interval, 25m distance filter) and `AppleSettings` (`allowBackgroundLocationUpdates: true`, `pauseLocationUpdatesAutomatically: true`, 25m distance filter). Permissions configured in `AndroidManifest.xml` and `Info.plist`. `flutter test` (12/12) and `flutter analyze` (0 issues) are green.
- **Status correction (July 22, 4th verification pass): CODE-COMPLETE, but NOT gate-verified.** Independent code read confirms the settings, all six Android permissions, both iOS usage strings + `UIBackgroundModes`, and that `main.dart:9` actually wires `OsLocationSource` into the running app (not dead code). **However the device gate — ledger fills while backgrounded, battery < 3%/day over ≥8 h — has never been run** (no physical device available to the verifying agent). D3 cannot be closed on code alone; see **Decision 5** for when to run it. Two follow-ups filed: **F8** (test covers only the host platform's branch) and **F9** (Android background-permission escalation may silently fail).
- **Accepted deviation:** `nativeVisits()` returns `null` on all platforms (`os_location_source.dart:25`). `geolocator` does not expose iOS `CLVisit`, and the design treats native visit events as an *optional corroborating hint* (`implementation_plan_foundation.md` §A2), not a requirement. Custom-clustering detection covers the need. **Do not re-flag this as a gap** — wiring CLVisit would require a bespoke platform channel and is not currently justified.

### Decision 4: Crypto + mDNS libraries on the Godot side (Phase 1)
Godot's built-in `Crypto` lacks X25519/AEAD and has no mDNS. We need libsodium (X25519 + HKDF + XChaCha20-Poly1305 secretstream) and an mDNS responder on the PC.
- **Option A**: A maintained libsodium GDExtension + an mDNS addon. Cost: vet/maintain third-party GDExtensions.
- **Option B**: A small custom GDExtension wrapping libsodium + a bundled mDNS lib. Cost: per-platform build pipeline, but full control.
- Recommendation: A if a maintained binding exists at build time; else B.
- **Your selection (July 21): Option A (maintained free GDExtension) if a trustworthy, current one exists at build time; otherwise Option B (wrap libsodium ourselves).** Hard rule either way: never hand-roll the crypto — standard libsodium underneath.
- **Status (verified July 22): UNSTARTED in code.** `sync_server.gd` is an in-process apply stub — no pairing, encryption, mDNS, or TCP transport on either side. Resolve via **agent-guide §5 (Item 3)**.

### Decision 5: When to run the D3 device gate (blocks closing Phase 0) — **needs your input**
D3 is code-complete but cannot be closed without a physical-device soak: carry a real phone ≥8 h of normal movement with the app **backgrounded**, then confirm (a) the scout ledger gained entries while backgrounded and (b) app battery attribution is **< 3%/day**. No verifying agent has a device, so this is the one task only you can perform. **Fix F9 first** — otherwise Android background permission may never engage and the soak proves nothing.
- **Option A — run it next, right after F9 lands.** Closes Phase 0 properly and de-risks the battery budget before more is built on it. Cost: one day of carrying the phone. *Recommended: the battery target is the assumption most likely to force a design change (falling back to Transistorsoft, D3 Option A), and you want to learn that early.*
- **Option B — batch it with the D4 device gate.** One combined session validates background capture *and* the Wireshark ciphertext check together. Cost: Phase 0 stays formally open for weeks; if the battery target fails you discover it after building transport on top.
- **Option C — defer to the Phase 8 hardening pass.** Cheapest now, riskiest later: a battery failure that late invalidates the capture strategy after everything depends on it.
- **Your selection (July 22): Option A — run the device soak immediately after F9 lands.** Rationale: the <3%/day battery target is the assumption most likely to force a design change (falling back to Transistorsoft, D3 Option A), and that must be discovered before Phase 1's transport and Phase 2's world generation are built on top of it. F9 must land first or the soak measures a permission that was never granted. **Phase 0 stays formally open until this runs** — see agent-guide §7 Phase 0.

---

## ✅ Resolved Decisions

### Decision 1 — Stack: Godot (PC) + Flutter (companion); LAN-only sync (Resolved July 21)
- **Selection**: PC game = **Godot 4** (free, 2D-first, clean Steam export); companion = **Flutter** (mature background location, matches the Gaslight toolchain).
- **Sync**: **LAN-only**, device-to-device, end-to-end encrypted. No server exists in v1.0. An internet relay is deferred to v1.1 and, if ever added, must preserve "server sees ciphertext only" (`design_companion_and_sync.md` §5).
- **Consequences**: two source trees — `game/` (Godot/GDScript) and `companion/` (Flutter/Dart); validation splits accordingly (agent guide §4). Detailed build steps live in `implementation_plan_foundation.md`.

### Decision 2 — Build the GPX replay harness in Phase 0 (Resolved July 21)
- **Selection**: build a debug-only GPX replay `LocationSource` on the companion that feeds recorded routes through the exact capture pipeline the OS would. E2E journeys 1–5 and automated pipeline tests depend on it.
- **Consequence**: added as a Phase 0 deliverable (`implementation_plan_foundation.md` §A8).

---

## 🧪 Resolved Issues & Implementation Refinements

**M1 — Phase 0 companion capture implemented & verified (July 22).** `implementation_plan_foundation.md` §A is realized: the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, `OsLocationSource`, and the scout-ledger UI. `flutter test` is **green** and `flutter analyze` has **0 issues**.

**M2 — Relocation math, grid projection, transactions & validation (July 22).**
- **F1 (fixed)**: `relocation_manager.gd` converted `body_lat/lon` and `home_cell` into a unified meters coordinate frame (`METERS_PER_DEGREE = 111000.0`, `CELL_METERS = 256.0`). Implemented out-of-contact fallback, minimal circle cell reveal, and nearest-revealed-tile snapping to player profile.
- **F2 (fixed)**: `sync_server.process_batch` is wrapped in `DB.begin_transaction()` / `commit_transaction()`, and explicit error paths (plus simulated batch failures) trigger `DB.rollback_transaction()`. `idempotent_sync_test.gd` verifies uncommitted state is safely discarded.
- **F3 (fixed)**: Unified cell (~256m) and tile (16m) grid projections across `sync_server.gd` and `relocation_manager.gd` matching `design_game_state_and_models.md`.
- **F5 (fixed)**: `test_runner.py` updated to run static linting and automatically execute headless Godot test runners (`godot --headless`) when Godot binary is detected.
- **F6 (fixed)**: Added `baseAccessMeters` (500m) to `tuning.json` and `config.gd`. `relocation_manager.gd` now thresholds `is_stranded` against game base-access radius instead of privacy fuzz.

**M2 confirmed (July 22, 3rd verification pass).** F2 and F6 independently re-verified in code: `base_access_meters = 500` is wired through `config.gd` ← `tuning.json` ← `relocation_manager.gd`; `process_batch` has a rollback path exercised by `idempotent_sync_test.gd` (replay-is-no-op + simulated mid-batch failure leaves no state). The `baseAccessMeters` constant was promoted into the design docs (master plan Core Configurations, `design_travel_and_time.md` §5, `design_game_state_and_models.md` §4) — previously it lived only in code. Two minor residuals folded into F4: (a) the `simulateFailure` flag is a test hook sitting in the production `process_batch` path — remove/guard it once real failure handling lands; (b) true crash-atomicity depends on real SQLite transactions (F4), since GDScript has no exception unwinding.

**M3 — Background capture implemented & closeout complete (July 22, 5th verification pass).**
- **What was solved:** `OsLocationSource` gained `buildLocationSettings()`, `AndroidSettings` (Foreground Service notification "Tenth Spring" / "Scouting your map", 2-min interval) and `AppleSettings` (`allowBackgroundLocationUpdates: true`, `pauseLocationUpdatesAutomatically: true`).
- **F8 (fixed):** `os_location_source_test.dart` uses `debugDefaultTargetPlatformOverride` to explicitly test both Android and iOS platform settings configurations.
- **F9 (fixed):** `OsLocationSource` implemented `isBackgroundPermissionGranted()` and `requestBackgroundPermission()`. `ScoutLedgerScreen` surfaces a non-blocking `Background scouting off — tap to enable` status banner routing to settings via `Geolocator.openAppSettings()`.
- **Promoted to design:** capture tuning values (25 m distance filter, 2-min interval) recorded in master plan Core Configurations and `design_privacy_and_location.md` §2.
- **DB accessor prep:** `db.gd:130,133` added `get_base_state()` / `set_player_tile()`, pre-clearing F4 caller churn.

---

## 🔎 Verification Findings — open, for the next agent

- **F4 (gap) — `db.gd` is an in-memory stub.** No SQLite, no persistence, no real migration framework — the §B2 DDL / §B6 migrations are not realized. Snapshot-transaction scaffolding exists but isn't real durability. Accessor prep is done (`get_base_state()`, `set_player_tile()` at `db.gd:130,133`; callers no longer touch private stores). **Agent-guide §4 (Item 2)**.
- **F7 (latent, found July 22 2nd pass) — home-cell size mismatch.** Companion `fuzzHome` snaps to a 300 m grid (`homeFuzzMeters`); the game treats the home cell as a 256 m `CELL_METERS` cell. These must reconcile when safehouse designation is wired (not yet implemented). **Agent-guide §6 (Deferred — trigger-gated).**
- **F8 (test-coverage gap, found July 22 4th pass) — platform settings test only exercises the host platform.** `companion/test/os_location_source_test.dart:15-26` branches on `defaultTargetPlatform`, which on a macOS CI host resolves to `macOS` — so the **Android assertions never run**. The Android foreground-service config is effectively unverified despite a green suite. Fix with `debugDefaultTargetPlatformOverride` to assert both branches. **Agent-guide §3 (Item 1)**.
- **F9 (risk, found July 22 4th pass) — Android background-permission escalation likely silently fails.** `os_location_source.dart:80-86` escalates by calling `Geolocator.requestPermission()` a second time when the grant is `whileInUse`. On Android 11+ that call does **not** grant `ACCESS_BACKGROUND_LOCATION` — the user must be routed to app settings. So background capture may never actually engage on Android despite a correct manifest, and the device soak would burn 8 h proving nothing. Add an explicit settings-redirect flow (`Geolocator.openAppSettings()`) with a rationale prompt, degrading gracefully per `design_privacy_and_location.md` §2. **Fix before running the device gate. Agent-guide §3 (Item 1)**.

---

## 📜 Design-Phase Decision Record (July 2026)

Founding decisions made with the user during the design brainstorm, recorded here so their rationale survives:

1. **Two-fog model** — real visits reveal (`known`), only in-game travel clears. Rationale: keeps real life as scouting and the game as the game; no one wins by commuting.
2. **Intel-never-inventory** for repeat visits — familiarity de-risks raids. Rationale: makes real habits meaningful without breaking pillar 1.
3. **15 mph travel** priced in time against real geography; UI speaks travel-time. Rationale: in-game effort must dwarf real effort so distance stays meaningful.
4. **Fast travel = physical presence** (anchored to the phone at sync time) + **stranded rule**. Rationale: the real world is the only teleporter; away-play becomes high-stakes survival, home becomes sacred.
   - **9. Platform: PC (Steam) game + thin phone companion** (added July 20, superseding the earlier phone-only app model). The companion is location capture + read-only map + sync *only* — no gameplay. Rationale: the payoff is sitting down at the PC "war room" to play tonight's raid from intel your phone gathered by day; keeping the phone thin protects that ritual and the battery. See `design_companion_and_sync.md`.
5. **Drop-and-recover death** (Minecraft-style) over deletion. Rationale: recovery runs are the tensest emergent quests; knowledge is immortal, stuff is mortal.
6. **Setting: a generation after the collapse** — blends overgrown + emptied + undead (user chose "mix of all 3"). Zombies roam by day; tiers Shambler/Stalker/Brute; colonies as the strategic clock.
7. **True pixel art** (D/P target) via licensed kit + commissions; AI for concepting only — AI raster sprite generation rejected as unreliable for frame-consistent pixel art.
8. **Name: "Tenth Spring"** — cleared against Steam/app stores/trademark search July 20, 2026 (domains + formal USPTO check still pending). Rejected: Dead Reckoning (crowded, incl. a zombie title), Fogwalker (existing app with the same GPS-fog mechanic — treat as prior art to differentiate from, not copy).
9. **Creature-collector (Pokémon) pivot considered and REJECTED (July 21)** — explored reskinning the game as a Pokémon-style collector. Rejected because using actual Pokémon assets/creatures/names in a commercial Steam release is copyright + trademark infringement (The Pokémon Company enforces aggressively), and it reverses the founding "avoid IP" reason. Also reaffirmed **OpenStreetMap, not Google Maps** (Google's ToS forbids replica/derivative map products). The genuinely good mechanics from the discussion were kept and adapted to zombies (items 10–12). If a creature collector is ever revived, it must use *original* creatures (Palworld / Temtem / Coromon precedent).
10. **Location-themed enemy variants (July 21)** — each zombie takes a `Biome` variant (distinct sprite + one signature trait) per cell: residential/downtown/industrial/retail/parkland/waterfront/institutional/wilds. Orthogonal to the 3 tiers. Rationale: thematic sprite variety — enemies look like where you are. See threats §1.1, art §1.1.
11. **Loot scales with horde difficulty (July 21)** — beyond the site's distance-based `dangerTier`, the toughest horde you actually defeat at a site boosts its loot roll. Rationale: choosing to fight harder is a real risk/reward lever. See resources §1.
12. **Landmark bosses (July 21)** — famous real POIs (national parks, monuments, stadiums) host fixed, hand-authored named apex bosses (tier 5, non-spreading, long respawn) dropping `unique` non-craftable loot. Rationale: real-world travel to famous places pays out the game's rarest loot — the zombie version of "legendaries at landmarks." See threats §3, resources §1–2.
13. **Expanded enemy system beyond 3 tiers (July 21)** — the 3 common tiers stay as the "mass"; added **special infected** archetypes (spitter/howler/grabber/charger/bloater/sentinel), a modular **attack-pattern** taxonomy, and **pack-composition combinations** where mixes (e.g. Grabber+Spitter = pinned in acid) force priority-target decisions. Rationale: user wants depth from *which threat to answer first*, not just more numbers. See threats §1.2–1.4.
14. **Loot icon set + concept sprites (July 21)** — 16×16 Minecraft-style item icons across the full taxonomy; rarity shown by slot border, not icon recolor; `unique` items get a glow. A 12-icon concept sheet establishes the style. Rationale: the game is looting-based, so items are their own (large but easy-to-source) art track. See art §1.2.
