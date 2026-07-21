# Threats & Colonies

This document defines the zombie tiers, the three power-scaling axes, and the colony lifecycle. The pillar: **the world pushes back** — ignore it and it closes in on your cleared territory and, eventually, your safehouse.

## 1. Zombie Tiers

```dart
enum ZombieTier { shambler, stalker, brute }
```

| Tier | Power | Behavior contract |
|---|---|---|
| `shambler` | 1 | Slow (×0.5 player speed). Everywhere. Threat is *crowds*: aggro chains to nearby shamblers. Harmless solo. |
| `stalker` | 2 | Fast (×1.1 player speed). Hunts by **sound**: locks onto noise events (see expeditions doc §3) within radius. Night doubles its lock-on radius. |
| `brute` | 3 | Slow but armored: immune to improvised weapons, damages gear on hit, breaks barricades. Requires crafted weapons or avoidance. Rare outside colonies. |

Zombies roam **day and night**. Daylight is safer, never safe.

## 2. Colony Lifecycle

A colony is a hive rooted in a dense POI (mall, hospital, downtown block). It is the mid/late-game strategic clock.

```dart
enum ColonyStage { nest, hive, warren, dominion }  // 1..4
```

- **Seeding**: when a region's revealed area crosses a density threshold, the highest-density uncleared PlaceNode rolls to seed a `nest`. Seeding is deterministic per world seed — no rubber-banding onto the player.
- **Growth**: every `colonyGrowthTickGameDays` (1), a colony gains progress; on stage-up it expands `territoryCells` outward — including into previously `cleared` cells, whose loot state can regress to `regrown` (guarded).
- **Pressure**: `raidPressure` accrues with stage and proximity to home. Crossing the threshold schedules a **base raid** (wave defense at the safehouse; composition = colony stage). Fortifications and watchpost warnings mitigate (see resources doc §4).
- **Assault**: each colony's root site is a dungeon: dense interior, stage-scaled population, one **apex zombie** (brute-plus with a stage modifier). Destroying the apex collapses the colony.
- **Pacification reward**: territory reverts over 2 game days, region danger tier drops by 1 for 30 game days, and the apex drops the game's top-tier loot + unique crafting components.

## 3. Power Scaling — Three Axes

Spawn tables are computed per cell from three multiplicative axes, so the player's real geography *is* the difficulty curve:

1. **Distance from home**: danger tier +1 per band (0–2 mi: base, 2–10: +1, 10–50: +2, 50+: +3). The home neighborhood is genuinely the starter zone.
2. **Urban density** (OSM building density): dense downtown breeds stalkers/brutes; suburbs and parks skew shambler.
3. **Time of day**: night = spawn count ×1.5, every unit's effective tier +1 (shamblers move faster, stalkers hear further, brutes gain armor), player light radius shrinks.

Colony territory overrides the floor: minimum danger = colony stage regardless of axes.

## 4. Fairness Contracts
- Danger is always **legible before commitment**: the destination chip shows danger tier and known colony influence before the player walks.
- No spawn may occur inside the player's screen-visible area ("no teleport ambushes") — spawns enter from off-screen edges or marked interior doors.
- The porch (3-minute home radius) never rolls encounters outside base-raid events.

## 5. Files (PC game)
* `game/systems/spawn_director` — per-cell spawn tables from the three axes.
* `game/systems/colony_engine` — seeding, growth ticks, pressure, collapse.
* `game/actors/zombie/*` — tier behaviors (one file per tier).
