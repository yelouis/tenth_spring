# Resources, Base & Economy

This document defines the POI → resource mapping, the item taxonomy, fuel/vehicles, and the safehouse systems. The pillar: **all value is earned in-game** — every item traces back to a raid.

## 1. POI Category → Resource Mapping

OSM tags map to `PlaceCategory`, which drives loot tables and map iconography:

| PlaceCategory | OSM sources (examples) | Primary loot | Secondary |
|---|---|---|---|
| `grocery` | supermarket, convenience, restaurant, cafe | Food | Water, containers |
| `medical` | pharmacy, hospital, clinic, dentist | Meds | Chemicals |
| `hardware` | hardware, doityourself, trade suppliers | Parts, tools | Weapon components |
| `fuel` | fuel station, garage | **Fuel units** | Vehicle parts |
| `apparel` | clothes, shoes | Armor materials | Fabric |
| `bigbox` | mall, department_store | Jackpot mixed | High zombie density |
| `park` | park, forest, allotments | Forage food, wood | Low danger |
| `civic` | school, library, office | Paper, misc | Maps intel bonus |
| `ruin` | unmapped buildings | Small mixed | — |
| `home` | player-designated | — (safehouse) | — |

Loot rolls scale with `dangerTier` — the frontier pays better. `bigbox` is the designed risk/reward spike.

## 2. Item Taxonomy

`ItemClass = { food, water, meds, fuel, parts, tools, weapon, armor, fabric, chemical, wood, special }`
- **Consumption**: food/water drain on a survival meter per game-hour awake (gentle in v1.0 — hunger weakens, never kills).
- **Weapons** degrade with use; brutes accelerate degradation (their role as gear-checks).
- **`special`**: apex-drop crafting components gating top recipes.

## 3. Fuel & Vehicles (Fuel = Reach)

- Fuel exists only as raid loot from `fuel` sites — the stations you actually drove past in real life literally power your in-game reach.
- Vehicles: `bicycle` (×2 speed, no fuel, silent), `car` (×6 speed, 1 fuel/3 real miles, noisy — raises encounter noise), `truck` (×5, 1 fuel/2 miles, +carry capacity).
- Vehicles are found (rare `fuel`/`bigbox` spawns), repaired with parts, and parked — they stay where you leave them on the map. A far-island expedition is: stage fuel → drive → raid → drive back, budgeted in game-days.

## 4. The Safehouse

- **Stash**: unlimited storage, accessible only at home (stranded rule).
- **Fortifications** (levels 0–3 each, built from parts/wood/tools): `walls`, `barricades` (slow brutes), `watchpost` (advance raid warning + composition preview), `workshop` (unlocks recipe tiers), `garden` (slow renewable food — the only non-raid resource, capped well below consumption so raids stay mandatory).
- **Base raids**: colony `raidPressure` events resolve as wave defense at the safehouse using placed fortifications; losses damage fortification levels, never the stash or the map.
- **Crafting**: recipes = parts + category materials at the workshop (weapons, armor, camp kits, decoys, repair kits, vehicle repairs).

## 5. Economy Contracts
- No purchases, no ads, no premium currency inside the loop — the memoir map must never feel farmed for monetization (pairs with the privacy pillar).
- No resource may be granted by any real-world event: not steps, not visits, not streaks. Enforced at the API level — the location subsystem literally has no write path into inventory tables.

## 6. Files (PC game)
* `game/config/poi_mapping` — OSM tag → category table (single source of truth).
* `game/config/loot_tables` — category × dangerTier rolls.
* `game/systems/crafting`, `game/systems/base_defense`, `game/systems/vehicle`.
