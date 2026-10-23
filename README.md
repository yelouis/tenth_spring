# Tenth Spring

A Pokémon game in the Diamond/Pearl style where **your map is the places you have actually been.** When you're somewhere new in real life, you open the phone companion and tap **Explore Here**. That reveals the neighbourhood (or park) on a fog-covered overworld built from real geography, which you then explore on PC — catching Pokémon in main-series turn-based battles. The phone never tracks you. Real life draws the map; everything on it is earned by playing.

**The setting:** a generation after a collapse. Half the houses have fallen in, grass grows through the streets, the cities stand empty, and the Ghost types have moved in. The fog over the unexplored world is the Distortion — reality only holds where people still walk. Cemeteries, ruins, and abandoned hospitals are thick with Ghost Pokémon; at night they are everywhere. Hauntings spread outward if left alone. Nine Wardens hold the line across the nine regions of the USA, and the Distortion has started learning *you*: at the end, you face the Echo — the fog wearing your face, leading a stronger copy of your own team. The full backstory is `docs/design_story_and_world.md`.

**How the Pokémon content works — read this first.** This is a non-commercial fan project. It contains **no Nintendo assets**. Like PokeMMO, the game asks you to import Pokémon ROMs **dumped from cartridges you own** — Pokémon Black or White for the Pokémon sprites, and Pokémon Emerald for the map's tiles — and reads them on your own machine.

**All 905 Pokémon of Generations 1–8 are included:**
- #650–905 use the [Smogon Sprite Project](https://www.smogon.com/forums/threads/smogon-sprite-project.3647722/)'s Black/White-style fan sprites (credited in-game and in `CREDITS.md`);
- species data comes from [PokéAPI](https://github.com/PokeAPI/pokeapi)'s open data;
- both are downloaded onto your machine on first run, and never stored in this repository. The project will never provide ROMs or help anyone find one. There is no Steam release, no sales, and no monetization. See `docs/design_rom_asset_pipeline.md`.

**Platform split:** the PC game holds all gameplay. The phone companion is deliberately thin — the Explore Here button, a list of the places you've explored, and reports to your PC — and contains no Pokémon content at all.

## Design pillars (settled — do not re-litigate)

1. **Two-fog model** — exploring a place in real life (Explore Here) turns it Unknown → Known (grey silhouette). You must then travel there *in-game* to explore it.
2. **Real movement unlocks access, never cargo** — walking around never grants items or Pokémon. It reveals places, landmarks, and events, which must still be explored and won in play.
3. **Intel, never inventory** — places you explore on many days in real life are easier to explore in-game (pre-mapped interiors, fewer encounters), never richer.
4. **Your real footsteps open the doors** — the map is made of famous places, and you can **Distort** from home only to places you've explored in real life (plus the famous city nearest home).
5. **Stranded** — your **PC box** and healing are at home. In a famous place you fight with the six you brought, and the only way home is that place's Waypost (or blacking out).
6. **Blackout drops the bag** — if your whole party faints you wake at home and your items stay where you fell, recoverable for a few days. Pokémon, the map, and the Pokédex are never lost.
7. **The world pushes back** — Ghost types own the night; hauntings spread from cemeteries and ruins and, ignored, will seal your PC.
8. **Privacy is a pillar** — the phone reads your location only when you tap a button, checks it on the phone, and forgets it. Only area names reach your PC, over a direct, end-to-end-encrypted link, and no location history exists anywhere. "Your map is yours."
9. **No Nintendo assets in this repository, ever** — the repo is public. ROMs and anything extracted from them live only on the player's machine.

## Documentation map

| Doc | Contract |
|---|---|
| `docs/agent_execution_guide.md` | **Start here** — how an engineering agent picks up this project |
| `docs/master_implementation_plan.md` | Phase order + tuning constants |
| `docs/design_famous_places.md` | **What the map contains** — the 27 cities, 60 parks and wonders, 78 legendary places, Warden landmarks; unlocking, Distort travel, the same map for everyone |
| `docs/design_interiors_and_quests.md` | **Enterable famous buildings** (each with a purpose), Pokémon-style puzzles, the 78 legendary challenges, and the 270+ side quests that reveal what happened |
| `docs/content_quest_roster.md` | The 110 city quests and 60 park quests, each revealing part of the story |
| `docs/design_story_and_world.md` | **The backstory and theme** — the Stillness, the Distortion, the nine Wardens, the Echo; every scene and system follows it |
| `docs/design_rom_asset_pipeline.md` | Bring-your-own-ROM importer, formats, cache, legal and repo guardrails |
| `docs/design_creatures_and_battles.md` | Stats, types, damage, status, catching, EXP, party, PC box, blackout |
| `docs/design_long_game.md` | Keeping the long game challenging once Pokémon get strong (Decision 35) |
| `docs/design_encounters_and_haunted_zones.md` | Spawn zones, ghost prevalence, levels, haunted zones, legendaries |
| `docs/design_expeditions_and_survival.md` | Exploring sites, haunted interiors, familiarity, healing scarcity |
| `docs/design_resources_and_base.md` | Items by place category, bag, home safehouse, bicycle |
| `docs/design_world_generation.md` | Explore Here → areas → OSM → tile overworld, tall grass, ruins, landmarks |
| `docs/design_game_state_and_models.md` | Data models and persistence |
| `docs/design_travel_and_time.md` | 15 mph rule, world clock, day/night, fast travel, stranded |
| `docs/design_companion_and_sync.md` | Companion scope, pairing, phone→PC sync |
| `docs/design_art_direction.md` | What art comes from the ROM vs. what is original; pixel spec |
| `docs/design_privacy_and_location.md` | One reading per tap, never kept; what leaves the phone |
| `docs/design_memory_and_resources.md` | Memory guards: tooling admission + watchdog, bounded and pausable heavy work in the game |
| `docs/implementation_plan_foundation.md` | Build steps for Phases 0–1 (Part A retired by Decision 29) |
| `docs/implementation_plan_explore_here.md` | The places pack, the companion's Explore Here, and the PC's unlocks |
| `docs/implementation_plan_famous_places.md` | The place list, the same map for everyone, unlocking, Distort |
| `docs/implementation_plan_world_generation_slice2.md` | The walkable Pokémon-style map, landmarks, and the ruin pass |
| `docs/e2e_testing_journeys.md` | Manual end-to-end test journeys |
| `docs/ongoing_general_errors.md` | Decisions, findings, engineering history |

## Stack

- **PC game: Godot 4.3.** SQLite for saves via the vendored `godot-sqlite` extension (Decisions 6–7). ROM import in pure GDScript.
- **Companion: Flutter** — Explore Here, the explored list, reports to the PC. No tracking, no gameplay, no Nintendo content.
- **Sync:** direct device-to-device over LAN — QR pairing, TLS with the PC's certificate pinned by the QR code (Decision 11), end-to-end encrypted.
- **Areas:** a small **places pack** (the famous places' neighbourhoods, from OpenStreetMap — © OpenStreetMap contributors, ODbL) ships inside both apps, so Explore Here works offline and the phone and PC always agree.
- **Map data:** OpenStreetMap, **fully offline** — the PC downloads one pinned snapshot of the state files containing the famous places you've unlocked — the map is 27 famous US cities and 60 famous parks and wonders (`docs/design_famous_places.md`) — once and reads it locally, so no map request ever names a place you've been (Decision 13). Never Google Maps — its terms forbid derivative map products.
- **Distribution:** the asset-free client via GitHub Releases; the companion via the app stores.

## Setup notes

On a Mac, set `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` before running the battery.

Configure git to use the repository's pre-commit hooks to ensure no prohibited ROM or Nintendo assets are committed:
```bash
git config core.hooksPath .githooks
```

### Memory guard for heavy commands
Heavy developer commands (Godot runs, Flutter test suites, spikes, map converters) run through the memory guard so they never exhaust machine memory:
```bash
python3 -I tools/memguard.py run <step> -- <command...>
```

### Run the PC game
Install **Godot 4.3** (stable, standard build — not .NET) from the official Godot site, and check the download against the release's `SHA512-SUMS.txt`. Open `game/project.godot` and press Play. The game opens at the home hub; **Distort** opens the Town Map of the places you can reach, and **Pair Companion** links your phone. The map is built from Pokémon-style pieces over your real streets (slice 2), drawn with original placeholder tiles; the real Pokémon tiles arrive once you import your own Emerald ROM.

### Install the companion on an iPhone (development build)
Needs a Mac with Xcode and Flutter.
1. Plug the iPhone into the Mac, unlock it, and tap **Trust**.
2. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (the phone restarts).
3. In Xcode, open `companion/ios/Runner.xcworkspace` → **Runner** target → **Signing & Capabilities** → set **Team** to your Apple ID (the free Personal Team works). If Xcode says the bundle identifier is unavailable, change `com.tenthspring.companion` to something unique, such as `com.<yourname>.tenthspring`.
4. From `companion/`, with the phone selected:
   ```bash
   flutter run --release
   ```
5. On the iPhone: **Settings → General → VPN & Device Management** → trust your developer certificate.

With a free Apple ID the app stops launching after 7 days; re-run step 4 to reinstall. A paid Apple Developer account removes that limit and enables TestFlight.

### Your own location data stays local
Demo point files, demo saves, and ROM dumps all live **outside** this repository. Never commit them — the repo is public.

## Status

Phases 0–1 (the companion, pairing, sync, persistence) are built; Explore Here replaces background capture (Decision 29, being built). The map — famous places, real streets in Pokémon pieces, unlocking, and Distort — is built and being given its ruined look (Decision 30). Everything Pokémon-specific is designed but not yet built. All `design_*.md` docs are contracts: implement exactly as specified, and file disagreements in `docs/ongoing_general_errors.md` as Decision blocks rather than silently deviating.
