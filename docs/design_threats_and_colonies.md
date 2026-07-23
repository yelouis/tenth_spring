# Threats & Colonies

This document defines the common infected, the special infected and their attack patterns, how pack *combinations* create emergent threats, location-themed biome variants, the three power-scaling axes, the colony lifecycle, and landmark bosses. The pillar: **the world pushes back** — ignore it and it closes in on your cleared territory and, eventually, your safehouse. Design intent: the depth is in **which threat you answer first**, not raw numbers.

## 1. Common Infected (the mass)

The three common tiers are the bulk of every encounter — the "mass" that specials (§1.2) turn dangerous.

```dart
enum ZombieTier { shambler, stalker, brute }   // common; specials are ZombieArchetype (§1.2)
```

| Tier | Power | Attack pattern | Behavior contract |
|---|---|---|---|
| `shambler` | 1 | `swipe` | Slow (×0.5). Everywhere. Threat is *crowds*: aggro chains to nearby shamblers. Harmless solo. |
| `stalker` | 2 | `lunge` | Fast (×1.1). Hunts by **sound** (expeditions §3); night doubles its lock-on radius. |
| `brute` | 3 | `slam` | Slow, armored: immune to improvised weapons, damages gear on hit, breaks barricades. |

Zombies roam **day and night**. Daylight is safer, never safe.

## 1.1 Biome Variants (location-themed sprites & behavior)

On top of the three tiers, every zombie takes a **biome variant** — a distinct sprite set plus one signature trait — drawn from the dominant character of the cell it spawns in (biome derived from OSM land use; see `design_world_generation.md` §3). This is the primary source of thematic sprite variety: the enemies you meet *look like where you are*.

```dart
enum Biome { residential, downtown, industrial, retail, parkland, waterfront, institutional, wilds }
```

| Biome | Derived from | Variant flavor + signature trait |
|---|---|---|
| `residential` | houses, suburbs | "Neighbors" — baseline; large slow packs |
| `downtown` | dense commercial/office | "Commuters" — stalker-heavy; tight sightlines |
| `industrial` | factories, warehouses | "Grinders" — brute-heavy, debris armor, hazards |
| `retail` | malls, shops | "Crowds" — huge shambler mobs (the `bigbox` spike) |
| `parkland` | parks, forest, green | "Verdant" — overgrown; hide in tall grass, ambush |
| `waterfront` | coast, rivers, docks | "Drowned" — bloated; burst on death |
| `institutional` | schools, hospitals, civic | "Wards" — fast, erratic stalkers |
| `wilds` | low-density, rural, fields | sparse — the frontier where landmark bosses lurk |

- **Orthogonal to tier**: a variant swaps *art + one trait*, never the core tier stats — so §1 (tiers) and §4 (scaling) stay intact. Biome selects *which skin/behavior*; danger level still comes from the three axes.
- **Content scope (flag for art)**: 3 tiers × 8 biomes ≈ 24 base enemy skins before specials and bosses — a real art budget. See `design_art_direction.md` for the matrix and a ship-first subset.

## 1.2 Special Infected (attack-pattern archetypes)

Beyond the mass, **specials** spawn in small numbers. Each is defined by a distinct attack pattern and a required counter — they are the reason encounters need *thought*, not just aim.

```dart
enum ZombieArchetype { spitter, howler, grabber, charger, bloater, sentinel }  // + the 3 commons
```

| Archetype | Role | Attack pattern | Counter | Biome affinity |
|---|---|---|---|---|
| `spitter` | area denial | `acidLob` — arcs acid into a lingering hazard pool | keep moving; break line of sight; kill at range | industrial, waterfront |
| `howler` | force multiplier | `summonPulse` — a scream that summons wanderers and speed-buffs the pack | silence it first — stealth or range | institutional, downtown |
| `grabber` | control | `grabPin` — ambushes from cover/tall grass and pins you until you struggle free or it's knocked off | mind cover lines; whittle before it reaches you | parkland |
| `charger` | burst | `chargeDash` — telegraphed straight-line rush: knockback + shatters barricades | sidestep the wind-up; use pillars/corners | downtown, industrial |
| `bloater` | hazard | `deathBurst` — slow; ruptures on death into a gas/acid cloud | kill at range, never melee; don't stand in the cloud | waterfront, retail |
| `sentinel` | alarm | `alarm` — stationary; on detecting you (sight/sound) it triggers a horde surge | stealth past, or snipe before it alerts | institutional, civic |

## 1.3 Attack-Pattern Taxonomy

Attack patterns are modular and data-driven, so new archetypes are new *combinations* of patterns, not new hardcoded actors:

```dart
enum AttackPattern { swipe, lunge, slam, acidLob, summonPulse, grabPin, chargeDash, deathBurst, alarm }
```
Each actor maps to one primary pattern (commons also have basic swipe/lunge/slam). Bosses (§3) chain several. A pattern owns its telegraph, hitbox/AoE, and cooldown so the same pattern reads identically wherever it appears.

## 1.4 Pack Composition & Combinations (the core of the difficulty)

The `spawn_director` assembles each encounter as a **pack** = a common mass (tier mix) + 0..N specials, weighted by biome, `dangerTier`, night, and colony stage. More danger → more specials and nastier mixes.

Individual specials are manageable; **the threat is the combination**, because mixes force priority targeting. These emerge from the weighting (not scripted set-pieces):

| Combo | Result | The decision it forces |
|---|---|---|
| Howler + crowd | **summoned surge** — a group becomes a wave | silence the Howler *now* |
| Grabber + Spitter | **pinned in acid** — the grab holds you in the hazard pool | don't hug cover while a Spitter is up |
| Charger + Bloater | **punt into gas** — the charge knocks you into the popped Bloater | kill the Bloater at range first |
| Grabber + Brute | **held for the slam** — pinned for the heavy hit | break the grab before the Brute lands |
| Spitter + Stalker | **zoned and chased** — acid forces you into the pursuer's lane | pre-clear one so they don't pincer |

Legibility still holds (§5): the site chip previews known special presence, and specials enter from off-screen edges / marked doors — never teleporting onto you.

## 2. Colony Lifecycle

A colony is a hive rooted in a dense POI (mall, hospital, downtown block). It is the mid/late-game strategic clock.

```dart
enum ColonyStage { nest, hive, warren, dominion }  // 1..4
```

- **Seeding**: when a region's revealed area crosses a density threshold, the highest-density uncleared PlaceNode rolls to seed a `nest`. Seeding is deterministic per world seed — no rubber-banding onto the player.
- **Growth**: every `colonyGrowthTickGameDays` (1), a colony gains progress; on stage-up it expands `territoryCells` outward — including into previously `cleared` cells, whose loot state can regress to `regrown` (guarded).
- **Pressure**: `raidPressure` accrues with stage and proximity to home. Crossing the threshold schedules a **base raid** (wave defense at the safehouse; composition = colony stage). Fortifications and watchpost warnings mitigate (see resources doc §4).
- **Assault**: each colony's root site is a dungeon: dense interior, stage-scaled population, one **apex zombie** (brute-plus with a stage modifier). Destroying the apex collapses the colony.
- **Pacification reward**: territory reverts over 2 game days, region danger tier drops by 1 for 30 game days, and the apex drops top-tier loot + unique crafting components.

## 3. Landmark Bosses

Famous real-world places — national parks, monuments, stadiums, major landmarks — are flagged as `landmark` sites during world generation (OSM tags; see `design_world_generation.md` §3 and the `landmark` category in `design_resources_and_base.md` §1). Each hosts a unique, hand-authored **named boss**: an apex threat above colony apexes, keyed to the landmark's biome, with a signature mechanic and a **guaranteed unique drop** (a named weapon/armor/trophy obtainable nowhere else).

- **Distinct from colony apexes**: colony apexes are *emergent* (hives grow wherever density allows); landmark bosses are *fixed* to specific famous real places and are a deliberate "pilgrimage" goal. A `parkland` national park hosts a giant Verdant apex; a `retail`/stadium hosts a Crowd horde-boss; etc.
- **Requires real reach**: the landmark must be unlocked, which usually means you physically went to (or traveled near) that famous place — so real-world travel to landmarks is the thing that pays out the game's rarest loot. This is the zombie-survival version of "legendaries at national parks."
- **Balance contract**: landmark bosses are danger tier 5, do **not** grow or spread (unlike colonies), and respawn only on a long cooldown (default: once per 30 game days) so their unique drops stay meaningful. Defeating one does not pacify a region (that's the colony reward) — the payoff is the unique loot and a permanent "cleared landmark" prestige marker on the map.
- **Legibility**: the site chip flags "Landmark — apex threat, unique loot" before the player commits.

## 4. Power Scaling — Three Axes

Spawn tables are computed per cell from three multiplicative axes, so the player's real geography *is* the difficulty curve:

1. **Distance from home**: danger tier +1 per band (0–2 mi: base, 2–10: +1, 10–50: +2, 50+: +3). The home neighborhood is genuinely the starter zone.
2. **Urban density** (OSM building density): dense downtown breeds stalkers/brutes; suburbs and parks skew shambler.
3. **Time of day**: night = spawn count ×1.5, every unit's effective tier +1 (shamblers move faster, stalkers hear further, brutes gain armor), player light radius shrinks.

Colony territory overrides the floor: minimum danger = colony stage regardless of axes. Landmark sites are fixed at tier 5. **Biome is not a fourth danger axis** — it selects the variant skin/behavior; its danger contribution is already captured by urban density, so never double-count it.

## 5. Fairness Contracts
- Danger is always **legible before commitment**: the destination chip shows danger tier, known colony influence, and any landmark-boss flag before the player walks.
- No spawn may occur inside the player's screen-visible area ("no teleport ambushes") — spawns enter from off-screen edges or marked interior doors.
- The porch (3-minute home radius) never rolls encounters outside base-raid events.

## 6. Files (PC game)
* `game/systems/spawn_director` — per-cell danger from the three axes **and pack composition** (mass + specials by biome/danger/night).
* `game/config/archetypes` — archetype → primary attack pattern + biome affinity table.
* `game/config/biome_variants` — biome × tier skin/behavior selection table.
* `game/config/landmark_bosses` — named boss definitions, chained patterns, unique drops.
* `game/systems/attack_patterns` — modular pattern behaviors (acid pool, charge dash, grab pin, death burst, alarm…), each owning its telegraph/hitbox/cooldown.
* `game/systems/colony_engine` — seeding, growth ticks, pressure, collapse.
* `game/systems/boss_encounter` — landmark boss fights (fixed, non-spreading).
* `game/actors/zombie/*` — common tier + special archetype actors.
