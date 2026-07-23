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
- **Status (verified July 22): UNSTARTED in code.** Only `GpxReplaySource` implements `LocationSource`; there is no `OsLocationSource` and no geolocation dependency in `pubspec.yaml`. Resolve via agent-guide §3 item 1.

### Decision 4: Crypto + mDNS libraries on the Godot side (Phase 1)
Godot's built-in `Crypto` lacks X25519/AEAD and has no mDNS. We need libsodium (X25519 + HKDF + XChaCha20-Poly1305 secretstream) and an mDNS responder on the PC.
- **Option A**: A maintained libsodium GDExtension + an mDNS addon. Cost: vet/maintain third-party GDExtensions.
- **Option B**: A small custom GDExtension wrapping libsodium + a bundled mDNS lib. Cost: per-platform build pipeline, but full control.
- Recommendation: A if a maintained binding exists at build time; else B.
- **Your selection (July 21): Option A (maintained free GDExtension) if a trustworthy, current one exists at build time; otherwise Option B (wrap libsodium ourselves).** Hard rule either way: never hand-roll the crypto — standard libsodium underneath.
- **Status (verified July 22): UNSTARTED in code.** `sync_server.gd` is an in-process apply stub — no pairing, encryption, mDNS, or TCP transport on either side. Resolve via agent-guide §3 item 3.

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

**M1 — Phase 0 companion capture implemented & verified (July 22).** `implementation_plan_foundation.md` §A is realized: the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, and the scout-ledger UI. `flutter test` is **green**, and the fuzz-only-persists invariant is honored (full-precision fixes stay in memory). No design change warranted — the implementation matches the contract. Remaining Phase 0 work (real `OsLocationSource`) is tracked under Decision 3.

---

## 🔎 Verification Findings (July 22) — open, for the next agent

A verification pass (docs + code) found these gaps/defects. They map to the agent-guide §3 queue. Godot was not installed in the verification environment, so `.gd` runtime tests were **not executed** (only `test_runner.py`'s static lint ran); item F5 addresses that.

- **F1 (bug) — relocation unit mismatch.** `game/scripts/relocation_manager.gd` subtracts a fuzzed *home cell index* (`home_cell_x/y`) from a *lat/lon degree* (`body_lat/lon`), so `distance_from_home_meters` / `is_stranded` are wrong. Also missing: nearest-revealed-tile snapping, unknown-area minimal-circle reveal, and the out-of-contact fallback (`implementation_plan_foundation.md` §B5). Agent-guide §3 item 4.
- **F2 (correctness) — non-transactional batch apply.** `sync_server.process_batch` applies rows without a single DB transaction (§B4.4); a mid-batch crash could advance `last_applied_seq` past partially-applied rows. Agent-guide §3 item 5.
- **F3 (consistency) — split coordinate grids.** `sync_server.latlon_to_cell` uses `×100` (~1.1 km cells) while `relocation_manager` uses `×1000` for the spawn tile, and neither matches the ~256 m cell / 16 m tile in the models doc. Pick one shared projection. Agent-guide §3 items 2/4.
- **F4 (gap) — `db.gd` is an in-memory stub.** No SQLite, no persistence, no real migration framework — the §B2 DDL / §B6 migrations are not realized. Agent-guide §3 item 2.
- **F5 (validation gap) — `.gd` tests never run.** `test_runner.py` is a Python static linter (syntax + token scan); the runtime assertions in `idempotent_sync_test` / `db_test` / `sync_ingest_isolation_test` require Godot headless in CI. Agent-guide §3 item 6.

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
