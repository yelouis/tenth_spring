# Tenth Spring

A Pokémon game in the Diamond/Pearl style set across **famous places of a ruined world.** You start by choosing the great city nearest your home, and the fog lifts there first. Inside a city you open its neighbourhoods one by one by playing; finishing a place pulls the fog back to the places next to it across a map of 27 famous US cities and 60 famous parks, monuments, and natural wonders — catching Pokémon in main-series Gen 8 turn-based battles along the way. Everything is earned in play, and the game reads no location.

**The setting:** a generation after a collapse. Half the houses have fallen in, grass grows through the streets, the cities stand empty, and the Ghost types have moved in. The fog over the unexplored world is the Distortion — reality only holds where people still walk. Cemeteries, ruins, and abandoned hospitals are thick with Ghost Pokémon; at night they are everywhere. Hauntings spread outward if left alone. Nine Wardens hold the line across the nine regions of the USA, and the Distortion has started learning *you*: at the end, you face the Echo — the fog wearing your face, leading a stronger copy of your own team. The full backstory is `docs/design_story_and_world.md`.

**How the Pokémon content works — read this first.** This is a non-commercial fan project. It contains **no Nintendo assets**. The world map runs out of the box with Tenth Spring's own recoloured public-domain (CC0) terrain and original building, ruin, landmark, and foliage sprites (`CREDITS.md`) — no GBA Emerald ROM is needed. Like PokeMMO, the game asks you to import a Pokémon Black or White ROM **dumped from a cartridge you own** for the Pokémon and trainer sprites, and reads it on your own machine.

**All 905 Pokémon of Generations 1–8 are included:**
- #650–905 use the [Smogon Sprite Project](https://www.smogon.com/forums/threads/smogon-sprite-project.3647722/)'s Black/White-style fan sprites (credited in-game and in `CREDITS.md`);
- species data comes from [PokéAPI](https://github.com/PokeAPI/pokeapi)'s open data;
- both are downloaded onto your machine on first run, and never stored in this repository. The project will never provide ROMs or help anyone find one. There is no Steam release, no sales, and no monetization. See `docs/design_rom_asset_pipeline.md`.

**Platform:** Tenth Spring is a standalone PC game built in Godot 4.3. All gameplay, saves, and map data live locally on your PC.

## Design pillars (settled — do not re-litigate)

1. **Two-fog model** — places open by play: you choose your starter city, and finishing a place opens the places next to it (Decision 86). Inside a city, a neighbourhood turns Unknown → Known (grey silhouette) when you pick it at the Waypost's board, and you must then go there *in-game* to explore it (Decision 54).
2. **Opening unlocks access, never cargo** — opening a city, park, or neighbourhood never grants items or Pokémon. It reveals places, landmarks, and events, which must still be explored and won in play.
3. **Intel, never inventory** — places where you spend more in-game days grow familiar and easier to explore (pre-mapped interiors, fewer encounters), never richer.
4. **The fog spreads outward from your starter city** — the map is made of famous places, and you can **Distort** from home to your starter city and to the places play has opened beside ground you've settled. Wild Pokémon grow stronger the farther you travel from home.
5. **Stranded** — your **PC box** and healing are at home. In a famous place you fight with the six you brought, and the only way home is that place's Waypost (or blacking out).
6. **Blackout drops the bag** — if your whole party faints you wake at home and your items stay where you fell, recoverable for a few days. Pokémon, the map, and the Pokédex are never lost.
7. **The world pushes back** — Ghost types own the night; hauntings spread from cemeteries and ruins and, ignored, will seal your PC.
8. **No location is ever read** — the game never asks where you really live or travel, stores no coordinates in your save, and sends nothing anywhere. "Your map is yours."
9. **No Nintendo assets in this repository, ever** — the repo is public. ROMs and anything extracted from them live only on the player's machine.

## Documentation map

*(Design docs live locally under `docs/`, ignored by git.)*

| Doc | Contract |
|---|---|
| `docs/agent_execution_guide.md` | **Start here** — how an engineering agent picks up this project |
| `docs/master_implementation_plan.md` | Phase order + tuning constants |
| `docs/design_famous_places.md` | **What the map contains** — the 27 cities, 60 parks and wonders, 78 legendary places, Warden landmarks; starter city, spread unlocking, Distort travel, park rules |
| `docs/design_neighbourhoods_and_caricature.md` | **Inside a city** — its Waypost camp, eight neighbourhoods opened by play, caricature maps, and routes along real roads |
| `docs/design_interiors_and_quests.md` | **Enterable famous buildings** (each with a purpose), Pokémon-style puzzles, the 78 legendary challenges, and the 270+ side quests that reveal what happened |
| `docs/content_quest_roster.md` | The 110 city quests and 60 park quests, each revealing part of the story |
| `docs/design_story_and_world.md` | **The backstory and theme** — the Stillness, the Distortion, the nine Wardens, the Echo; every scene and system follows it |
| `docs/design_rom_asset_pipeline.md` | Bring-your-own-ROM importer, formats, cache, legal and repo guardrails |
| `docs/design_creatures_and_battles.md` | Gen 8 battle rules, stats, types, damage, status, catching, EXP, party, PC box, blackout |
| `docs/implementation_plan_battle_engine.md` | Phase 5 battle-engine architecture and slice roadmap |
| `docs/design_long_game.md` | Keeping the long game challenging once Pokémon get strong (Decision 35) |
| `docs/design_encounters_and_haunted_zones.md` | Spawn zones, ghost prevalence, levels, haunted zones, legendaries |
| `docs/design_expeditions_and_survival.md` | Exploring sites, haunted interiors, familiarity, healing scarcity |
| `docs/design_resources_and_base.md` | Items by place category, bag, home safehouse, bicycle |
| `docs/design_world_generation.md` | Areas, familiarity, OSM tile overworld, tall grass, ruins, landmarks |
| `docs/design_game_state_and_models.md` | Data models and persistence |
| `docs/design_travel_and_time.md` | 15 mph rule, world clock, day/night, fast travel, stranded |
| `docs/design_art_direction.md` | What art comes from the ROM vs. what is original; pixel spec and 960 × 640 integer scaling |
| `docs/design_privacy_and_location.md` | No location read, zero coordinates in saves |
| `docs/design_memory_and_resources.md` | Memory guards: tooling admission + watchdog, bounded and pausable heavy work in the game |
| `docs/e2e_testing_journeys.md` | Manual end-to-end test journeys |
| `docs/ongoing_general_errors.md` | Decisions, findings, engineering history |

## Stack

- **PC game: Godot 4.3.** SQLite for saves via the vendored `godot-sqlite` extension (Decisions 6–7). ROM import in pure GDScript.
- **Areas:** a small **places pack** (`game/data/places_pack_v1.json.gz`, from OpenStreetMap — © OpenStreetMap contributors, ODbL) stays on the PC for the places that haven't yet received caricature maps.
- **Map data:** OpenStreetMap, **fully offline** — the PC downloads one pinned snapshot of the state files containing the famous places you've unlocked — 27 famous US cities and 60 famous parks and wonders (`docs/design_famous_places.md`) — once and reads it locally, so no map request ever names where you live (Decision 13). Never Google Maps — its terms forbid derivative map products.
- **Distribution:** the asset-free PC client via GitHub Releases.

## Setup notes

On a Mac, set `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` before running the battery.

Configure git to use the repository's pre-commit hooks to ensure no prohibited ROM or Nintendo assets are committed:
```bash
git config core.hooksPath .githooks
```

### Memory guard for heavy commands
Heavy developer commands (Godot runs, spikes, map converters) run through the memory guard so they never exhaust machine memory:
```bash
python3 -I tools/memguard.py run <step> -- <command...>
```

### Launching Godot
Always launch Godot through `python3 -I tools/godot.py` (which enforces `--headless`, an absolute `--path <repo>/game`, refuses `--script` files that do not extend `SceneTree` or `MainLoop`, and refuses `--script`, `-s`, or `--script=...` after `--` so Godot cannot open the game on the real save).

**In a fresh clone or a new git worktree, import the project once before running any test** — otherwise every script that uses `class_name` fails to parse (F58):
```bash
python3 -I tools/godot.py --memguard-step godot_import --import
```

Never run a `*_test.gd` file directly with `--script`; to run a single test, use:
```bash
python3 game/tests/test_runner.py --only <test_name>
```

### Run the PC game
Install **Godot 4.3** (stable, standard build — not .NET) from the official Godot site, and check the download against the release's `SHA512-SUMS.txt`. Open `game/project.godot` and press Play. On a fresh save, the home hub asks you to choose your starter city; once chosen, **Distort** opens the Town Map of the places you can reach. Washington DC is built as a caricature city (camp, eight neighbourhoods, ten routes, and 94 interiors) drawn out of the box with Tenth Spring's own recoloured CC0 terrain (`original_v1.{png,json}`) and original building, ruin, landmark, and prop sprites (`game/assets/original/`).

### Keep saves and ROM dumps local
Demo saves, ROM dumps, and any local caches all live **outside** this repository. Never commit them — the repo is public.

## Status

Phases 1–4 are built for Washington DC: SQLite saves and migrations, the bring-your-own-ROM importer and Gen 8 data pack, the caricature city (Waypost camp, eight neighbourhoods, ten routes, 94 interiors, original art and optional Emerald runtime tiles), walking, the clock, the board and lamps, doors, dialogue, pickups, safe resume, and 960 × 640 integer scaling. Phase 5 (the Gen 8 battle engine) is underway: Slice 1's event core, Gen 8 damage/accuracy formulas, and dual-oracle verification are in place. Other cities and parks still use the street-accurate map until the DC walkthrough approves the rollout. All `design_*.md` docs are contracts: implement exactly as specified, and file disagreements in `docs/ongoing_general_errors.md` as Decision blocks rather than silently deviating.
