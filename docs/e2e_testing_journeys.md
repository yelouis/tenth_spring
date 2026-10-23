# End-to-End (E2E) Testing Journeys

This document defines the key player journeys and step-by-step manual instructions to test the E2E integrity of the companion→PC pipeline, two-fog reveal, travel economy, stranded/death rules, and colony pressure. Explore Here journeys need a real phone — mock location set to a public point works — or `tools/demo_import.py --points` (Decision 29), plus a paired PC build.

---

## 💾 Journey 0: ROM Import (Bring Your Own ROM)

**Objective**: Verify the game runs without a ROM, imports valid dumps, rejects bad ones, and never lets Nintendo content near the repo. Requires a Pokémon Black or White (USA) ROM — and, for the map's tiles, a Pokémon Emerald (USA) ROM — **that the tester dumped from their own cartridges**, never downloaded ones. Each import works without the other: no Emerald means the placeholder map tiles; no Black/White means no Pokémon content.
1. Fresh install, no ROM. Launch the PC game → verify it reaches the map in "no ROM" mode with placeholder silhouettes and a clear "import your ROM" prompt; onboarding, pairing, and sync all work.
2. Offer a non-ROM file and a ROM with the wrong game code → both rejected with plain-language messages; no partial cache is left behind.
3. Import the valid dump(s) → progress shown; `user://rom_cache/manifest.json` written last; the §7 validation passes (649 species, 559 moves; Giratina is Ghost/Dragon; Spiritomb is Ghost/Dark; Chandelure is Ghost/Fire; Chandelure's sprite decodes to a real image, not static).
4. Kill the game mid-import, relaunch → the old cache (or none) is intact and import resumes cleanly.
5. Run `git status` in the repo → **nothing** from the ROM or cache appears; `tools/check_no_nintendo_assets.py` passes. Copy a `.nds` into the repo and stage it → the check **fails**.

## 🗺️ Journey 1: Setup Day (PC Tutorial → Pairing → First Sync → First Reveal)

**Objective**: Verify the two-device onboarding, consent flow, and the sync-time reveal from install to a personal map.

### 📋 Steps to Test:
1. Fresh install both builds. Launch the **PC game** → tutorial establishes the fantasy and prompts "recruit your scout" with a pairing QR.
2. Install the **companion**, scan the QR. Verify the phone pins the PC's certificate fingerprint and the PC shows the phone as paired (no secret leaves either device). Pair a second phone from a fresh QR → the first phone's next sync is refused (`unpaired`), and its already-synced history is still on the map.
3. Tap **Explore Here** for the first time. Verify the canonical rationale (`design_privacy_and_location.md` §3), that only "While Using" is requested, and that the OS settings offer no "Always".
4. Tap **Set home**. Verify the phone names a starting city and stores nothing else. After the next report, the PC has that city on its Distort list with its Waypost neighbourhood revealed.
5. Inside a famous place, tap **Explore Here**. Verify the message (`New neighbourhood — …`), and that the explored list shows the place by name only. Tap it again: `Already explored`. Outside every famous place: `This spot isn't on Tenth Spring's map.`
6. **Report to PC.** Verify the neighbourhood turns `known`, the Town Map lights the city, and **inventory is completely unchanged** (cartography, never cargo).
7. Verify the phone outbox is acked empty, a replayed batch is a no-op, and neither database holds a coordinate (the phone's has no real-number column; every REAL value in the PC save is NULL).

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

## ✈️ Journey 4: Stranded (Distort and the Waypost)

**Objective**: Verify Distort, the Waypost rule, and the stranded rule.
1. With a party of 6 and more Pokémon in the PC box, Distort from home to an explored city. Verify you arrive at its Waypost, with the arrival banner.
2. Walk away from the Waypost. Verify the PC box can't be used, the party and bag are exactly what you brought, and a newly caught Pokémon still deposits remotely.
3. Quit the game away from the Waypost and relaunch. Verify you resume in that place — never sent home for free.
4. Walk back to the Waypost and Distort home. Verify PC access returns with no penalty.

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
5. Explore a park → its legendary waits at its lair behind its challenge; catch or defeat it → it's gone for good in this save (`design_famous_places.md` §6).

## 🔒 Journey 7: Privacy Audit (Release Gate)

**Objective**: Verify the pillar-level guarantees across both devices.
1. Over a day of normal phone use, the OS shows the companion's location access as "While Using" and never shows a background-location indicator.
2. Sniff the sync channel: the phone→PC payload is ciphertext. In a development build's decrypted frame log, every row holds only `kind`, `placeId`, `areaKey`, and `tsUtcMs`. Sniff PC traffic: the only map-data traffic is whole-state file downloads the player confirmed; no request contains coordinates or names a cell.
3. "Export my map" (PC) produces valid GeoJSON; "Erase everything" wipes the phone outbox + pairing **and** the PC world, returning both builds to first-launch state.
