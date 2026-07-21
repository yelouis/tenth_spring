# Expeditions & Survival

This document defines the raid loop (the core moment-to-moment game), the noise/stealth model, how familiarity intel cashes out, and the roguelite death contract.

## 1. The Raid Loop

Arriving at a `known` PlaceNode and entering it starts a raid on its **site map** (interior tilemap, generated deterministically from category + size + `cellSeed`).

```
APPROACH  → exterior read: visible zombies, entry choices (door/window/roof)
ENTER     → interior; dark beyond light radius unless intel pre-reveals
SCAVENGE  → loot containers (category loot table); every action emits noise
COMPLICATE→ noise/time raises alert stages: quiet → stirred → hunted
EXTRACT   → leave with what you carry; place → `cleared`, loot → `partial/stripped`
```

- **Time passes during raids** (world clock keeps running) — a greedy scavenge can cost you the daylight you needed to walk home. The extract prompt always shows the current trek-home time and daylight remaining.
- **Carry capacity forces choices**: loot exceeds capacity by design at mid+ tier sites; taking the generator means leaving the meds.
- Clearing is not all-or-nothing: extracting early still marks `cleared` with `partial` loot — you can come back, but regrowth/colony pressure may beat you to it.

## 2. Familiarity Cash-Out (Intel, Never Inventory)

| IntelLevel | Effect at raid start |
|---|---|
| `known` (1 real visit) | Nothing pre-revealed. Blind entry. |
| `familiar` (3+) | Layout + exits pre-mapped; −25% ambush rolls. |
| `mastered` (10+) | Full interior incl. loot spots; −50% ambush; guaranteed escape route marked. |

Your real-life regulars become the raids you run confidently; the one-visit gas station three states away is terrifying. **No intel level ever grants items.**

## 3. Noise & Stealth

- Every action has a noise value (walk 1, jog 2, sprint 4, pry/loot 3, smash 6, gunshot 10). Noise emits an event circle; stalkers within lock on, shamblers drift toward it.
- Alert stages per site: `quiet` (ambient wander) → `stirred` (converging) → `hunted` (active pursuit + off-screen reinforcements from marked doors).
- Crouched movement halves noise; thrown objects create decoy noise events. This is the entire stealth model — no vision cones in v1.0.

## 4. Death & Recovery (Roguelite Contract)

- On death: carried inventory drops as a `DeathCache` at the death tile; the survivor wakes at the safehouse (or, if stranded far from home, at the nearest cleared friendly tile on that island) with empty hands and full HP.
- **The map, familiarity, cleared states, base, and stash always persist.** Knowledge is immortal; stuff is mortal.
- The cache persists `deathCacheDecayGameDays` (3 game days), marked on the map with a countdown. Recovering it means returning — possibly into the colony that killed you. One cache max; a second death merges into the newest site.
- **No other death penalty** — no XP loss, no map loss, no fortification damage. Death sets up the game's tensest quest (the recovery run) rather than erasing progress.

## 5. Files (PC game)
* `game/systems/site_generator` — deterministic interiors per category/size/seed.
* `game/systems/raid_controller` — loop states, alert stages, extract prompts.
* `game/systems/noise_model` — emission values, propagation, lock-on.
* `game/systems/death_handler` — cache drop/merge/decay, respawn placement.
