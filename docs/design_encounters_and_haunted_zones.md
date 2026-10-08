# Encounters & Haunted Zones

This document defines where wild Pokémon appear, which ones, at what level, why Ghost types dominate the collapsed world, how haunted zones spread and get cleansed, and where legendaries live. The pillar carried over from the original design: **the world pushes back** — ignore a haunting and it creeps toward home.

Species are referenced by **National Dex number** in repo data; names shown here are for readability only and come from the player's ROM at runtime (`design_rom_asset_pipeline.md` §1).

---

## 1. Where encounters happen

| Tile | Encounters |
|---|---|
| **Tall grass** | Each step rolls `grassEncounterRate = 0.10` |
| **Haunted interiors** (abandoned buildings, ruins — explored per `design_expeditions_and_survival.md`) | Each step rolls 0.12; draws from the haunted pool only |
| **Water** | Out of v1 scope (needs a Surf-equivalent; later phase) |
| Paths, roads, the home porch | None — except haunting intrusions (§5.4) |

Repel (bag item) suppresses encounters whose level is below the lead party Pokémon's level, for its step count.

## 2. Spawn zones

Each map cell carries one **zone**, derived deterministically from OSM tags (`design_world_generation.md` §3). Each zone has two weighted pools: **regular** and **haunted** (Ghost, Dark, and eerie Psychic species).

| Zone | OSM sources (examples) | Base ghost share | Regular pool emphasis (dex) | Haunted pool (dex) |
|---|---|---|---|---|
| `residential` | `landuse=residential` | 0.05 | Normal/Flying: Starly 396, Bidoof 399, Glameow 431 | Murkrow 198, Misdreavus 200 |
| `downtown` | dense commercial/office | 0.08 | Psychic/Steel: Abra 63, Magnemite 81 | Gastly 92, Stunky 434 |
| `industrial` | `landuse=industrial`, `brownfield` | 0.05 | Poison/Steel/Electric: Grimer 88, Koffing 109, Voltorb 100, Trubbish 568 | Bronzor 436, Golett 622 |
| `retail` | malls, `shop=*` clusters | 0.08 | Normal: Meowth 52, Glameow 431 | Duskull 355, **Rotom 479** (§6) |
| `parkland` | parks, forest, meadow, scrub | 0.06 | Grass/Bug: Budew 406, Kricketot 401, Oddish 43 | Shuppet 353, Hoothoot 163 |
| `waterfront` | coast, riverbank, docks | 0.05 | Water: Psyduck 54, Buizel 418, Shellos 422 | Drifloon 425, Frillish 592 |
| `institutional` | schools, civic buildings | 0.12 | Psychic: Chingling 433, Drowzee 96 | Duskull 355, Misdreavus 200, Litwick 607 |
| `wilds` | low-density rural, fields | 0.06 | Varied, higher level | Murkrow 198, Gastly 92 |
| **`cemetery`** | `landuse=cemetery`, `amenity=grave_yard` | **0.60** | Normal: Bidoof 399 | **Gastly 92, Haunter 93, Duskull 355, Dusclops 356, Shuppet 353, Misdreavus 200, Yamask 562** |
| **`ruins`** | `historic=ruins`, `building=ruins`, `abandoned:*`, `disused:*` | **0.45** | Rock/Psychic: Unown 201, Bronzor 436 | Sableye 302, Gastly 92, Haunter 93, Yamask 562, Golett 622 |
| **`hospital`** | `amenity=hospital` | **0.30** | Psychic: Chingling 433, Hypno 97 | Duskull 355, Misdreavus 200, Litwick 607, Lampent 608 |

The roster spans all 649 Gen 1–5 species (Decision 12). Gen 5's Ghost lines are placed where they fit the setting: Litwick/Lampent in hospitals and institutions, Yamask in cemeteries and ruins, Golett in ruins and industry, Frillish at the waterfront. Their final forms (Chandelure, Cofagrigus, Golurk, Jellicent) come from evolution, or appear as zone bosses (§5). The full weighted tables live in `game/config/spawn_tables.json` (dex numbers + weights only). These are **starting content**, tunable in Phase 11 balance.

## 3. Ghost prevalence — the horror undertone, as a formula

```
nightMult  = 3.0 at night, 1.5 at dusk, 1.0 otherwise   (bands: design_travel_and_time.md §1)
ghostShare = clamp(zoneBase · nightMult + 0.10 · hauntStage, 0, 0.80)
roll < ghostShare → draw from the haunted pool; else → regular pool
```
So a quiet suburb by day is 5% ghost; that same suburb at night inside a stage-3 haunting is 45%; a cemetery at night hits the 80% cap. The cap keeps every encounter table from collapsing into a single type.

## 4. Levels — real geography is the difficulty curve

| Distance from home | Wild level band |
|---|---|
| 0–2 mi | 2–10 |
| 2–10 mi | 8–22 |
| 10–50 mi | 18–38 |
| 50+ mi | 30–55 |

Modifiers: +2 at night for haunted-pool draws; +2 per haunt stage inside haunted territory; zone bosses = band max + 5. Players get stronger by **actually traveling** — the furthest places hold the strongest Pokémon.

## 5. Haunted zones (replaces zombie colonies)

### 5.1 Stages
```dart
enum HauntStage { none, whisper, haunt, shroud, distortion }   // 0..4
```

### 5.2 Seeding
When a region's revealed area crosses a density threshold, the most "haunted" uncleansed site (`cemetery` > `ruins` > `hospital`) rolls to seed a **whisper**. Deterministic per world seed — never rubber-banded toward the player.

### 5.3 Growth
Every `hauntGrowthTickGameDays = 1`, a zone gains progress; on stage-up its territory expands outward by one ring of cells, **including into cells the player has cleared**. Territory cells receive the §3 ghost-share and §4 level bonuses and a visual distortion tint.

### 5.4 Pressure on home
When a stage-3+ zone's territory comes within **2 cells** of the home safehouse, ghost encounters begin on the porch ("intrusion"). At **stage 4 adjacent to home, the PC box is sealed** until the intrusion is driven back by defeating the zone's boss. That is the stake that replaces zombie base raids: let a haunting grow and you lose access to your stored Pokémon.

### 5.5 Cleansing
Each zone's root site is a haunted interior with a **zone boss** — a high-level Ghost Pokémon chosen by stage (e.g. whisper: Haunter 93 · haunt: Banette 354 · shroud: Mismagius 429 · distortion: Dusknoir 477). Each stage's boss pool also includes Gen 5 ghosts: haunt adds Lampent 608; shroud adds Cofagrigus 563 and Jellicent 593; distortion adds Chandelure 609 and Golurk 623. **Defeating or catching the boss cleanses the zone**: territory reverts over 2 game days and the bonuses vanish. Catching it means you keep a powerful ghost. Rewards: ghost-themed items — Spell Tag, Reaper Cloth, Dusk Stone, Dusk Balls (`design_resources_and_base.md`).

## 6. Real-world-gated events

These tie Ghost legends to the core twist — **things you must physically do in real life**:
- **Spiritomb (442):** finding the Odd Keystone at a `ruins` site, then having **physically visited 32 distinct haunted real places** (cemeteries, ruins, hospitals), awakens Spiritomb at the home safehouse — an echo of Platinum's 32-encounter requirement.
- **Rotom (479):** appears at night in abandoned electronics stores (`shop=electronics` inside `retail`).

## 7. Landmark legendaries

- Landmark sites (national parks, monuments, stadiums, attractions — `design_world_generation.md` §3) host a legendary from a pool keyed to the landmark archetype, defined by dex number in `game/config/landmark_legendaries.json`. Example: large natural lakes inside parks → the lake guardians Uxie 480 / Mesprit 481 / Azelf 482 (level 50).
- **Unique per save.** Once caught, a legendary never spawns again. If it faints without being caught, it returns after `legendaryRespawnGameDays = 30`.
- **Requires real reach** — the landmark must be revealed, meaning the player physically went there or near it.
- **The final arc — Giratina (487, level 70).** After **5 haunted zones** are cleansed, the Distortion that fogs the unexplored world gathers at the player's most-visited landmark, and Giratina appears. *(This is the narrative frame in `README.md`: the fog is the Distortion, and reality only holds where people still walk.)*

## 8. Legibility and fairness

- A site's chip shows its zone, ghost activity (low/medium/high, from §3), level band, haunt stage, and — once revealed — "something stirs here" for an uncaught legendary, before the player commits to travel.
- No encounters in the 3-minute home porch except §5.4 intrusions.

## 9. Files (PC game)
* `game/encounters/encounter_roller.gd` — per-step rolls, Repel.
* `game/encounters/spawn_director.gd` — zone pools, §3 ghost share, §4 levels.
* `game/config/spawn_tables.json`, `game/config/landmark_legendaries.json` — dex numbers + weights only.
* `game/world/haunt_engine.gd` — seeding, growth ticks, intrusion, cleansing.
* `game/world/events.gd` — real-world-gated events (Spiritomb, Rotom).
