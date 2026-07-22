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
| `landmark` | national_park, monument, attraction, stadium, viewpoint | **Unique boss drop** | Trophy, rare crafting |
| `ruin` | unmapped buildings | Small mixed | — |
| `home` | player-designated | — (safehouse) | — |

Loot rolls scale with `dangerTier` — the frontier pays better. `bigbox` is the designed risk/reward spike. `landmark` sites gate the game's rarest loot behind an apex boss (see `design_threats_and_colonies.md` §3).

### Loot scales with horde difficulty, not just distance

Beyond the site's baseline `dangerTier`, the *specific horde you defeat* raises the payout. A **horde** is a grouped encounter with a difficulty score:

```
hordeDifficulty = f(size, tierMix, biomeModifier, isNight)
```

- Clearing a raid site rolls its loot on a table whose quality is boosted by the **hardest horde you actually beat** there — so choosing to fight a big night-time Brute pack instead of sneaking past is a real risk/reward lever, on top of distance.
- Extraction still respects carry capacity: a fat horde-difficulty roll can exceed what you can haul, forcing choices (see `design_expeditions_and_survival.md` §1).
- **Landmark bosses** roll on a dedicated `landmark_loot` table of unique, named, non-craftable items — the top of the whole economy, available only from landmark apexes and only once per cooldown.

## 2. Item Taxonomy

`ItemClass = { food, water, meds, fuel, parts, tools, weapon, armor, fabric, chemical, wood, special, unique }`
- **Consumption**: food/water drain on a survival meter per game-hour awake (gentle in v1.0 — hunger weakens, never kills).
- **Weapons** degrade with use; brutes accelerate degradation (their role as gear-checks).
- **`special`**: colony-apex crafting components gating top recipes.
- **`unique`**: named, non-craftable landmark-boss drops (signature weapons/armor + display trophies). One-of-a-kind identity rewards; the reason to make a pilgrimage to a far-off famous place.

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
* `game/config/poi_mapping` — OSM tag → category table (single source of truth; includes `landmark`).
* `game/config/loot_tables` — category × dangerTier × hordeDifficulty rolls.
* `game/config/landmark_loot` — unique named drops per landmark boss.
* `game/systems/crafting`, `game/systems/base_defense`, `game/systems/vehicle`.
