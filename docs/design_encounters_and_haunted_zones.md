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

The roster spans all 905 Gen 1–8 species (Decision 32). Gen 5's Ghost lines are placed where they fit the setting: Litwick/Lampent in hospitals and institutions, Yamask in cemeteries and ruins, Golett in ruins and industry, Frillish at the waterfront. Their final forms (Chandelure, Cofagrigus, Golurk, Jellicent) come from evolution, or appear as zone bosses (§5). The full weighted tables live in `game/config/spawn_tables.json` (dex numbers + weights only). These are **starting content**, tunable in Phase 11 balance.

### 2a. Where in the USA (Decision 18 = A for the Pokédex, 2026-10-19)
Zones say *what kind of place*; Decision 18 adds *where in the country*, so that the size of the USA matters (`design_story_and_world.md` §7):
- **Biome per cell** — desert, forest, coast, mountains, wetland, plains, snow, or city — from real land cover and climate. The data source and rule are fixed in the slice that builds spawns (slice 3), using public-domain US federal data where possible.
- **Region per cell** — one of the 9 US Census divisions (DC, Puerto Rico, and the US Virgin Islands count as South Atlantic).
- **Every species gets a home:** about a third live **everywhere**, about 40% only in certain **biomes**, about 20% only in **one region**, and the **legendary and mythical** species (82, at 78 places — Decision 32) are bound to one region's great landmarks (§7).
- Spawn tables gain `biomes` and `region` keys per entry (dex numbers only). A zone pool entry is eligible in a cell only if the cell's biome and region allow it.

## 3. Ghost prevalence — the horror undertone, as a formula

```
nightMult  = 3.0 at night, 1.5 at dusk, 1.0 otherwise   (bands: design_travel_and_time.md §1)
ghostShare = clamp(zoneBase · nightMult + 0.10 · hauntStage, 0, 0.80)
roll < ghostShare → draw from the haunted pool; else → regular pool
```
So a quiet suburb by day is 5% ghost; that same suburb at night inside a stage-3 haunting is 45%; a cemetery at night hits the 80% cap. The cap keeps every encounter table from collapsing into a single type.

## 3a. Distortion Fields (2026-10-19 — the human's addition to Decision 18)

Thin spots where the Distortion's copies bleed through (`design_story_and_world.md` §6). **Starting values — tunable in `tuning.json`:**
- **When:** a field opens about once every `distortionFieldIntervalGameDays = 3` game days. That drops to 2 once the player holds 6 or more Anchors (the Echo escalating, story §5.1).
- **How long:** `distortionFieldDurationGameDays = 1`.
- **Where:** a revealed cell containing tall grass inside the famous place the player is in, within `distortionFieldRadiusMiles = 10` ground miles of the player's position when it opens. No field opens while the player is at home. The field covers the `distortionFieldSizeCells = 5` × 5 cells centred there.
- **Seeding:** deterministic from `(worldSeed, game-day index)`, never steered toward the player's needs.
- **Encounters inside a field:** each tall-grass encounter draws from the **field pool** with probability `distortionFieldForeignShare = 0.40`; otherwise it draws from the normal zone pools.
  - The field pool is **every non-legendary, non-mythical species**, ignoring biome and region, weighted equally.
  - Levels use the local §4 band.
  - The §3 ghost share still applies to the non-field draws.
- **Never** legendary or mythical species — they can't be copied. So the Pokédex can never be finished at home (§7).
- **Ultra Beasts** (Decision 32) appear **only** in fields, and only once Necrozma has been caught or defeated (`design_famous_places.md` §1.4).
  - They are 1 in 50 of field-pool draws, and only in fields that open after the player holds 6 or more Anchors.
  - They aren't copies; they come from somewhere else through the thinnest fog.
- **Legibility:** fields are drawn with the distortion tint, and a chip reads `Distortion Field — <h> h left`.

## 4. Levels — real geography is the difficulty curve

| Distance from home | Wild level band |
|---|---|
| 0–2 mi | 2–10 |
| 2–10 mi | 8–22 |
| 10–50 mi | 18–38 |
| 50+ mi | 30–55 |

Modifiers: +2 at night for haunted-pool draws; +2 per haunt stage inside haunted territory; zone bosses = band max + 5. Players get stronger by **actually traveling** — the furthest places hold the strongest Pokémon.
- **Extended across the country** (Decision 35, so a team can reach Warden strength by travelling): 50–300 mi 30–50 · 300–1,000 mi 42–62 · 1,000–2,000 mi 55–75 · 2,000 mi or more 65–85. These replace the single 50+ mi row (`design_long_game.md` §4.2).
- **"Home" here means the starter city** (Decision 29: no home location reaches the PC).

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
- **Spiritomb (442):** find the Odd Keystone at a `ruins` site. Then send **Explore Here reports from 32 distinct areas** (neighbourhoods or parks) that each contain a cemetery, ruin, or hospital, and Spiritomb wakes at the home safehouse — an echo of Platinum's 32-encounter requirement. *(Amended for Decision 29: the unit is now an explored area.)*
- **Rotom (479):** appears at night in abandoned electronics stores (`shop=electronics` inside `retail`).

## 7. Famous places: legendaries, Warden trials, and the finale

Since 2026-10-20 the map contains only **famous places**: 27 cities and 60 parks, monuments, and wonders (`design_famous_places.md`, Decisions 25–26). Legendaries and Wardens live there.

### 7.1 Legendaries (Decisions 18 and 26)
- **Where:** each of the 78 legendary places holds **its own** legendary or mythical species, never two in one spot. The other 4 of the 82 species come by evolution (Decision 32). The table — dex number, place, region, theme — is `design_famous_places.md` §1.2, and the config is `game/config/famous_places.json`.
- **Requires real reach:** the place must be unlocked by a real visit (for a spot inside a city, its neighbourhood), then reached in-game from the Waypost.
- **A challenge stands in the way:** a maze or puzzle in front of its lair, generated from `(dex number, MAP_SEED)` so it's the same for every player. The themes and lore requirements are in `design_famous_places.md` §6.
- **One decisive battle:** catching it **or** defeating it ends it forever, and both count for the Pokédex. Blacking out or fleeing doesn't use up the chance — redo the challenge and try again. *(This replaces `legendaryRespawnGameDays`, which is retired.)*
- **Giratina (487)** is an ordinary legendary, at Carlsbad Caverns.

### 7.2 Pokédex completion
The Pokédex is complete when every non-legendary species is **caught**, and every legendary and mythical species is **caught or defeated**. Distortion Fields (§3a) can supply any non-legendary species anywhere; legendaries always require travel.

### 7.3 Warden trials (Decisions 18 and 26)
- **Nine Wardens,** one per region (`design_story_and_world.md` §4), each at **one fixed landmark** (`design_famous_places.md` §5).
- **A Warden appears only after all three of the region's cities are fully unlocked** (`design_famous_places.md` §3.2).
- **Team levels — fixed, never relative** (Decision 35): every Warden fields a **level-75** team, built like a competitive team and played by the strongest AI. Each trial applies its region's survival rule (story §4 table). *(Replaces `22 + 6 × anchorsHeld`.)*
- **Winning** grants that region's **Anchor** (a key item) and its perk.
- **Each region's survivors** — three named trainers, one per city (story §4a) — field fixed **level-50** teams. After the region's Warden, their "Old Friends" rematches are at **80**, and the Warden's own rematch at **90** (Decision 35; replaces `18 + 6 × anchorsHeld`).
- The names, types, rules, and perks are starting content, tunable.

### 7.4 The finale — the Echo (replaces the Giratina arc)
- **Unlocked by holding all nine Anchors.**
- **Where:** the famous place explored on the most distinct days (Explore Here reports, Decision 29). The player Distorts there and walks from the Waypost.
- **The battle:** a perfected mirror of the player's current party. The same species, at the player's levels + 5 (**cap 100**), with IVs 31, competitive EV spreads, and competitive natures, abilities, held items, and movesets from everything each species can learn (`design_long_game.md` §4.3). The strongest AI tier, and no bag items on either side. *(Decision 35: at level 100 the Echo's edge is the build, not the level.)*
- **Before it:** the escalating Echo encounters in `design_story_and_world.md` §5.1 — Hollow Trainers at 3+ Anchors, more frequent fields at 6+.

## 8. Legibility and fairness

- A site's chip shows its zone, ghost activity (low/medium/high, from §3), level band, haunt stage, and — once revealed — "something stirs here" for an uncaught legendary, before the player commits to travel. A major landmark's chip also names the region's Warden and whether their Anchor is held.
- No encounters in the 3-minute home porch except §5.4 intrusions.

## 9. Files (PC game)
* `game/encounters/encounter_roller.gd` — per-step rolls, Repel.
* `game/encounters/spawn_director.gd` — zone pools, §3 ghost share, §4 levels.
* `game/config/spawn_tables.json`, `game/config/landmark_legendaries.json` — dex numbers + weights only.
* `game/world/haunt_engine.gd` — seeding, growth ticks, intrusion, cleansing.
* `game/world/events.gd` — real-world-gated events (Spiritomb, Rotom).
* `game/world/distortion_fields.gd` — §3a scheduling, placement, and the field pool.
* `game/story/wardens.gd`, `game/story/echo.gd` — §7.3 trials and §7.4 finale.
* `game/config/regions.json` — state → region; `game/config/wardens.json` — Warden teams, rules, and perks (dex numbers only).
