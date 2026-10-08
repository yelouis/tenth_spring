# End-to-End (E2E) Testing Journeys

This document defines the key player journeys and step-by-step manual instructions to test the E2E integrity of the companion→PC pipeline, two-fog reveal, travel economy, stranded/death rules, and colony pressure. Location-dependent journeys require a real phone with mock-location tooling (or a scripted GPX replay harness on the companion — build in Phase 0) plus a paired PC build.

---

## 💾 Journey 0: ROM Import (Bring Your Own ROM)

**Objective**: Verify the game runs without a ROM, imports a valid dump, rejects bad ones, and never lets Nintendo content near the repo. Requires a Pokémon Platinum (USA) ROM **the tester dumped from their own cartridge** — never a downloaded one.
1. Fresh install, no ROM. Launch the PC game → verify it reaches the map in "no ROM" mode with placeholder silhouettes and a clear "import your ROM" prompt; onboarding, pairing, and sync all work.
2. Offer a non-ROM file and a ROM with the wrong game code → both rejected with plain-language messages; no partial cache is left behind.
3. Import the valid dump → progress shown; `user://rom_cache/manifest.json` written last; the §7 validation passes (493 species; Giratina is Ghost/Dragon; Spiritomb is Ghost/Dark; a sprite decodes to a real image, not static).
4. Kill the game mid-import, relaunch → the old cache (or none) is intact and import resumes cleanly.
5. Run `git status` in the repo → **nothing** from the ROM or cache appears; `tools/check_no_nintendo_assets.py` passes. Copy a `.nds` into the repo and stage it → the check **fails**.

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

## 🌿 Journey 2: First Catch (Known → Explored)

**Objective**: Verify travel, tall-grass encounters, a full battle, and catching on a nearby revealed place.
1. From home, open the destination chip for a `known` park ~1 mile away. Verify ~4 min travel time, a green daylight badge, zone `parkland`, ghost activity "low", level band 2–10.
2. Walk there. Verify the world clock is charged for the distance and no encounters roll on the porch or roads.
3. Walk through tall grass until an encounter starts (≈ every 10 steps on average). Weaken the wild Pokémon with damaging moves; check damage numbers against the Gen IV formula for the shown stats.
4. Throw a Poké Ball. Verify the shake count follows the catch formula; on success the Pokémon joins the party (or deposits remotely if the party is full) and its Pokédex entry records this place's category and cell.
5. Verify the place becomes `cleared` and its sprites/names come from the ROM cache — and that nothing in the save file contains a name or sprite, only numbers.

## 🌙 Journey 3: Caught Out at Night

**Objective**: Verify the Ghost surge, Dusk Ball, and that being far from home at night is genuinely dangerous.
1. Leave late afternoon toward a cemetery with an amber daylight badge; linger until night.
2. At night in the cemetery, run 30 encounters → most should be Ghost-type (the ghost share caps at 80%). Back in a suburb by day, Ghost types should be rare.
3. Throw a Dusk Ball at night → verify the ×3.5 modifier is applied (compare against a Poké Ball on a matching target).
4. Walk home in the dark with a weakened party. Verify no forced teleport and no healing until home — surviving the trek is the content.

## ✈️ Journey 4: Stranded (Fast Travel = Real Body)

**Objective**: Verify phone-anchored relocation and the stranded rule.
1. With a party of 6 and more Pokémon in the PC box, mock-relocate the **phone** 200+ miles and sync. Start a PC session (e.g. on a laptop on that network).
2. Verify: the player spawns at the synced `bodyFix` on a minimal revealed circle; banner reads distance-from-home; the PC box cannot be withdrawn from or swapped; the party and bag are exactly what was brought; a newly caught Pokémon still deposits remotely.
3. Verify the trek-home option prices the full real distance at 15 mph (multi-game-day estimate); mock-relocating the phone home + syncing restores PC access with no penalty.
4. **Out-of-contact fallback**: start a PC session with the phone unreachable → verify spawn at last synced body position with the "scout out of contact" banner, never blocked or teleported home.

## 🕯️ Journey 5: Blackout & Recovery

**Objective**: Verify the blackout contract.
1. Let the whole party faint in a haunted interior while carrying items. Verify: you wake at home with the party fully healed; a `BagCache` sits at the blackout tile with a 3-game-day countdown; **no Pokémon is lost**; the map, Pokédex, and PC are intact.
2. Return and recover the bag before expiry → items merge back. Black out elsewhere first → verify the single-cache merge rule.
3. Let a cache expire → items are permanently gone and the map marker disappears.

## 👻 Journey 6: A Haunting Spreads (Long-Arc)

**Objective**: Verify the world pushes back. (Use a debug time-warp harness.)
1. Reveal a region containing a cemetery; verify a haunted zone seeds there deterministically.
2. Warp growth ticks: stage-ups expand territory, ghost share and wild levels rise inside it, and the distortion tint deepens.
3. Let a stage-3 zone's territory reach within 2 cells of home → ghost encounters start on the porch. At stage 4 → the PC box is sealed.
4. Enter the root site, beat or catch the zone boss → the zone is cleansed, the PC unseals, and territory reverts over 2 game days.
5. Reveal a lake inside a national park → a legendary is assigned; catch it → it never spawns again in this save.

## 🔋 Journey 7: Battery & Privacy Audit (Release Gate)

**Objective**: Verify the pillar-level guarantees across both devices.
1. 48-hour phone carry with capture on: battery attribution < 3%/day.
2. Sniff the sync channel: the phone→PC payload is ciphertext (no plaintext coordinates on the wire); precision never exceeds storage-fuzzed (~110 m). Sniff PC traffic: Overpass queries are cell-region-scoped and only for revealed cells; nothing leaves the PC containing coordinates (Steam Cloud, if on, carries only the fuzzed save).
3. "Export my map" (PC) produces valid GeoJSON; "Erase everything" wipes the phone outbox + pairing **and** the PC world, returning both builds to first-launch state.
