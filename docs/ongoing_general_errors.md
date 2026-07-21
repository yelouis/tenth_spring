# Ongoing General Errors & Engineering History

## Overview
This document tracks key engineering insights, regression-risk pitfalls, open decisions, and historical system updates for Tenth Spring. Major architectural design layers are documented in dedicated system design files under `docs/`. Format mirrors Gaslight's conventions: issues are numbered, decisions get options + a `Your selection:` line, and resolved items move to the Resolved section with what-was-solved.

---

## 🔴 Open Decisions

### Decision 1: Confirm Two-Build Stack (blocks Phase 1)
The game is now **PC (Steam) + thin phone companion**. This decouples the engine choice: the PC engine needs great 2D/tilemap + Steam export and no longer needs mobile background-location plugins (that burden moves entirely to the companion, which does no gameplay). README Decision 0 assumes **PC = Godot 4, companion = Flutter**.
- **Option A (assumed)**: PC = Godot 4 + companion = Flutter. Best 2D tooling + free Steam export on PC; Flutter keeps the companion's background-geolocation story mature and matches the Gaslight toolchain.
- **Option B**: PC = Flutter + Flame (desktop build) + companion = Flutter. One language/toolchain for both; weaker Steam/desktop-2D ergonomics than Godot.
- **Option C**: PC = Unity + companion = native/Flutter. Best tilemap tooling; licensing + build-size overhead for a 2D game.
- Sync sub-decision: LAN-only device-to-device (assumed) vs. add an E2E-encrypted relay for off-network sync (v1.1 candidate — see `design_companion_and_sync.md` §5).
- Your selection: _(pending)_

### Decision 2: GPX Replay Harness Scope (blocks Journey testing)
E2E journeys need scripted location. Build a debug-only GPX replay harness in Phase 0 (recommended — journeys 1–4 depend on it), or rely on platform mock-location tools only?
- Your selection: _(pending)_

---

## 🧪 Resolved Issues & Implementation Refinements

_None yet — no code exists. First entries expected from Phase 0 (background-capture battery tuning and platform-permission edge cases are the predicted early residents of this file)._

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
