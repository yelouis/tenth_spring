# Expeditions & Survival

This document defines exploring a revealed place in-game: searching sites for items, haunted interiors, how real-world familiarity pays off, healing scarcity, and blacking out. The survival undertone of the original design survives the Pokémon pivot through three rules: **healing only happens at home, the bag drops when you black out, and far from home you only have your party** (`design_creatures_and_battles.md` §11).

---

## 1. Exploring a site

Arriving at a `known` PlaceNode and entering it opens its **site map** — an interior tilemap generated deterministically from `(category, size, cellSeed)`.

```
APPROACH → the site chip shows zone, ghost activity, level band, haunt stage
ENTER    → interior; dark beyond the light radius unless intel pre-reveals it
SEARCH   → item spots roll on the category's item table (design_resources_and_base.md §1)
ENCOUNTER→ steps in tall-grass patches or haunted rooms roll encounters
LEAVE    → place becomes `cleared`; item spots → `partial` / `stripped`
```
- **The world clock keeps running inside.** A long search can cost the daylight you needed to get home before the ghosts surge. The leave prompt always shows travel time home, daylight remaining, and the party's total HP %.
- Leaving early still marks the place `cleared` with `partial` items. You can come back; haunting growth may get there first.

## 2. Haunted interiors

Abandoned buildings, ruins, hospitals, and cemetery chapels generate **haunted interiors** (in the spirit of Platinum's Old Chateau): darker, encounters draw only from the haunted pool, and the **Dusk Ball bonus applies** (`design_creatures_and_battles.md` §9). A haunted zone's root site is always a haunted interior, with the zone boss in its deepest room (`design_encounters_and_haunted_zones.md` §5.5).

## 3. Familiarity — intel, never inventory

Repeat real-world visits raise a place's intel level. Familiarity **never grants items or Pokémon** — it makes the in-game visit safer and more efficient.

| IntelLevel (real visits) | Effect when exploring |
|---|---|
| `known` (1+) | Interior dark; standard encounter rate |
| `familiar` (3+) | Layout and item spots pre-revealed; encounter rate −25% |
| `mastered` (10+) | Full interior mapped; encounter rate −50%; exit route marked |

Your real-life regular spots become places you can sweep confidently. The cemetery you walked past once, three towns over, is the frightening one.

## 4. Healing scarcity

There are no Pokémon Centers — the world collapsed. **Full healing happens only at the home safehouse.** In the field, the party heals only from bag items found while exploring. Deciding when to turn back is the core expedition tension.

## 5. Blacking out and recovery

- If every party Pokémon faints: wake at home, party fully healed.
- **The bag's contents drop at the tile where you blacked out**, kept as a `BagCache` for `bagCacheDecayGameDays = 3`, marked on the map with a countdown. Recovering it means going back — possibly into the haunting that beat you.
- At most one cache exists; blacking out again merges into a cache at the newest location.
- **Pokémon are never lost.** The map, intel, Pokédex, and PC always persist.

## 6. Site item state

`untouched → partial → stripped → regrown`. Regrowth is slow and driven by haunting proximity (haunted territory "resurfaces" items over time), **never** by real-world visits.

## 7. Files (PC game)
* `game/explore/site_generator.gd` — deterministic interiors per `(category, size, cellSeed)`.
* `game/explore/site_controller.gd` — enter / search / leave, the leave prompt.
* `game/explore/bag_cache.gd` — blackout drop, merge, decay, recovery.
