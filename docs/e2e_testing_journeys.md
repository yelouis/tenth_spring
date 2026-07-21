# End-to-End (E2E) Testing Journeys

This document defines the key player journeys and step-by-step manual instructions to test the E2E integrity of the companion→PC pipeline, two-fog reveal, travel economy, stranded/death rules, and colony pressure. Location-dependent journeys require a real phone with mock-location tooling (or a scripted GPX replay harness on the companion — build in Phase 0) plus a paired PC build.

---

## 🗺️ Journey 1: Setup Day (PC Tutorial → Pairing → First Sync → First Reveal)

**Objective**: Verify the two-device onboarding, consent flow, and the sync-time reveal from install to a personal map.

### 📋 Steps to Test:
1. Fresh install both builds. Launch the **PC game** → tutorial establishes the fantasy and prompts "recruit your scout" with a pairing QR.
2. Install the **companion**, scan the QR. Verify pairing derives a shared key on both devices (no key leaves either device) and the PC shows the phone as paired.
3. Companion permission ask: verify the canonical rationale copy (`design_privacy_and_location.md` §3) and that declining "Always" still works ("While Using" + manual "scout here").
4. Designate the safehouse **on the PC**. Verify the stored home is the fuzzed cell, not the raw point (inspect PC DB) and the fuzz circle is shown.
5. Carry the phone on a normal errand (or replay a GPX trace with ≥2 dwells ≥120 s). Verify the companion ledger lists the day's visits by **name only** — no map reveal on the phone.
6. Return to the same network, start a **PC session**. Verify: the sync pulls the visit batch, the **intel ceremony** plays (fog peels, chips stamp, route draws), corridor tiles render `known` grey, visited POIs show name + category + "?" chip, and **inventory is completely unchanged** (cartography, never cargo).
7. Verify the phone outbox is acked empty and a replayed batch is a no-op.

## 🥾 Journey 2: First Raid (Known → Cleared)

**Objective**: Verify the travel economy and raid loop on a nearby revealed place.
1. From the safehouse, open the destination chip for a `known` grocery ~1 mile away. Verify it shows ~4 min travel time and a green daylight badge.
2. Walk there in-game. Verify world-clock charge matches distance, and encounter rolls occur outside the porch only.
3. Enter → verify blind interior (1 visit = `known` intel). Loot food; make noise until `stirred`; extract.
4. Verify place → `cleared` full color, loot state `partial`, stash unchanged until items are deposited at home.

## 🌙 Journey 3: Caught Out at Night

**Objective**: Verify day/night danger and the no-teleport-punish rule.
1. Depart late afternoon toward a target with an amber daylight badge. Linger scavenging until dusk.
2. Verify night: spawn ×1.5, tier bump, shrunken light radius, stalker lock-on radius doubled.
3. Walk home in the dark. Verify no forced teleport/timeout — surviving the trek is the content.

## ✈️ Journey 4: Stranded (Fast Travel = Real Body)

**Objective**: Verify phone-anchored relocation and the stranded rule.
1. With loot in `carried` and more in the stash, mock-relocate the **phone** 200+ miles and sync. Start a PC session (e.g. on a laptop on that network).
2. Verify: survivor spawns at the synced `bodyFix` on a minimal revealed circle; banner reads distance-from-home; stash is inaccessible; carried inventory is exactly what was carried.
3. Verify the trek-home option prices the full real distance at 15 mph (multi-game-day estimate); mock-relocating the phone home + syncing restores stash access with no penalty.
4. **Out-of-contact fallback**: start a PC session with the phone unreachable → verify spawn at last synced body position with the "scout out of contact" banner, never blocked or teleported home.

## 💀 Journey 5: Death & Recovery

**Objective**: Verify the roguelite contract.
1. Die inside a raid carrying items. Verify: `DeathCache` at death tile with 3-game-day countdown; respawn at safehouse, empty hands; map/intel/cleared states fully intact.
2. Recover the cache before expiry → verify merge into inventory. Die again elsewhere first → verify single-cache merge rule.
3. Let a cache expire → verify permanent loss and map marker removal.

## 🐝 Journey 6: Colony Pressure (Long-Arc)

**Objective**: Verify the world pushes back. (Use a debug time-warp harness.)
1. Reveal a dense region; verify deterministic colony seeding at the densest uncleared POI.
2. Warp growth ticks: verify stage-ups expand territory, previously `cleared` cells regress to `regrown`, and danger floors override the three axes inside territory.
3. Let `raidPressure` cross threshold near home → verify a scheduled base raid resolves as wave defense, damages fortification levels only (never stash/map), and watchpost previews composition.
4. Assault the colony root, kill the apex → verify collapse, 2-game-day territory reversion, −1 region danger for 30 game days, apex `special` drop.

## 🔋 Journey 7: Battery & Privacy Audit (Release Gate)

**Objective**: Verify the pillar-level guarantees across both devices.
1. 48-hour phone carry with capture on: battery attribution < 3%/day.
2. Sniff the sync channel: the phone→PC payload is ciphertext (no plaintext coordinates on the wire); precision never exceeds storage-fuzzed (~110 m). Sniff PC traffic: Overpass queries are cell-region-scoped and only for revealed cells; nothing leaves the PC containing coordinates (Steam Cloud, if on, carries only the fuzzed save).
3. "Export my map" (PC) produces valid GeoJSON; "Erase everything" wipes the phone outbox + pairing **and** the PC world, returning both builds to first-launch state.
