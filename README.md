# Tenth Spring

A Pokémon game in the Diamond/Pearl style where **your map is the places you have actually been.** A phone companion app passively records where you go in real life; that movement reveals a fog-covered overworld generated from your real geography, which you then explore on PC — catching Pokémon in main-series turn-based battles. Real life draws the map; everything on it is earned by playing.

**The setting:** a generation after a collapse. The streets are overgrown, the cities stand empty, and the Ghost types have moved in. The fog over the unexplored world is the Distortion — reality only holds where people still walk. Cemeteries, ruins, and abandoned hospitals are thick with Ghost Pokémon; at night they are everywhere. Hauntings spread outward if left alone. Nine Wardens hold the line across the nine regions of the USA, and the Distortion has started learning *you*: at the end, you face the Echo — the fog wearing your face, leading a stronger copy of your own team. The full backstory is `docs/design_story_and_world.md`.

**How the Pokémon content works — read this first.** This is a non-commercial fan project. It contains **no Nintendo assets**. Like PokeMMO, the game asks you to import Pokémon ROMs **dumped from cartridges you own** — Pokémon Black or White for the Pokémon, and Pokémon Emerald for the map's tiles — and reads sprites, species data, moves, names, and tiles from them on your own machine. All 649 Pokémon of Generations 1–5 are included. The project will never provide ROMs or help anyone find one. There is no Steam release, no sales, and no monetization. See `docs/design_rom_asset_pipeline.md`.

**Platform split:** the PC game holds all gameplay. The phone companion is deliberately thin — location capture, a read-only memoir map, and sync — and contains no Pokémon content at all.

## Design pillars (settled — do not re-litigate)

1. **Two-fog model** — a real visit turns a place Unknown → Known (grey silhouette). You must then travel there *in-game* to explore it.
2. **Real movement unlocks access, never cargo** — walking around never grants items or Pokémon. It reveals places, landmarks, and events, which must still be explored and won in play.
3. **Intel, never inventory** — places you visit often in real life are easier to explore in-game (pre-mapped interiors, fewer encounters), never richer.
4. **Your real body opens the doors** — the map is made of famous places, and you can **Distort** from home only to places you've physically been (plus the famous city nearest home). A session starts wherever your phone is, if that's in a famous place.
5. **Stranded** — your **PC box** and healing are at home. In a famous place you fight with the six you brought, and the only way home is that place's Waypost (or blacking out).
6. **Blackout drops the bag** — if your whole party faints you wake at home and your items stay where you fell, recoverable for a few days. Pokémon, the map, and the Pokédex are never lost.
7. **The world pushes back** — Ghost types own the night; hauntings spread from cemeteries and ruins and, ignored, will seal your PC.
8. **Privacy is a pillar** — location processing stays on your own devices, home coordinates are fuzzed, and phone→PC sync is direct and end-to-end encrypted. "Your map is yours."
9. **No Nintendo assets in this repository, ever** — the repo is public. ROMs and anything extracted from them live only on the player's machine.

## Documentation map

| Doc | Contract |
|---|---|
| `docs/agent_execution_guide.md` | **Start here** — how an engineering agent picks up this project |
| `docs/master_implementation_plan.md` | Phase order + tuning constants |
| `docs/design_famous_places.md` | **What the map contains** — the 27 cities, 36 parks and wonders, 48 legendary places, Warden landmarks; unlocking, Distort travel, the same map for everyone |
| `docs/design_story_and_world.md` | **The backstory and theme** — the Stillness, the Distortion, the nine Wardens, the Echo; every scene and system follows it |
| `docs/design_rom_asset_pipeline.md` | Bring-your-own-ROM importer, formats, cache, legal and repo guardrails |
| `docs/design_creatures_and_battles.md` | Stats, types, damage, status, catching, EXP, party, PC box, blackout |
| `docs/design_encounters_and_haunted_zones.md` | Spawn zones, ghost prevalence, levels, haunted zones, legendaries |
| `docs/design_expeditions_and_survival.md` | Exploring sites, haunted interiors, familiarity, healing scarcity |
| `docs/design_resources_and_base.md` | Items by place category, bag, home safehouse, bicycle |
| `docs/design_world_generation.md` | GPS → visits → OSM → tile overworld, tall grass, landmarks |
| `docs/design_game_state_and_models.md` | Data models and persistence |
| `docs/design_travel_and_time.md` | 15 mph rule, world clock, day/night, fast travel, stranded |
| `docs/design_companion_and_sync.md` | Companion scope, pairing, phone→PC sync |
| `docs/design_art_direction.md` | What art comes from the ROM vs. what is original; pixel spec |
| `docs/design_privacy_and_location.md` | Location permissions, on-device processing, fuzzing |
| `docs/design_memory_and_resources.md` | Memory guards: tooling admission + watchdog, bounded and pausable heavy work in the game |
| `docs/implementation_plan_foundation.md` | Build steps for Phases 0–1 |
| `docs/e2e_testing_journeys.md` | Manual end-to-end test journeys |
| `docs/ongoing_general_errors.md` | Decisions, findings, engineering history |

## Stack

- **PC game: Godot 4.3.** SQLite for saves via the vendored `godot-sqlite` extension (Decisions 6–7). ROM import in pure GDScript.
- **Companion: Flutter** — location capture, read-only memoir map, sync. No gameplay, no Nintendo content.
- **Sync:** direct device-to-device over LAN — QR pairing, TLS with the PC's certificate pinned by the QR code (Decision 11), end-to-end encrypted.
- **Map data:** OpenStreetMap, **fully offline** — the PC downloads one pinned snapshot of the state files containing the famous places you've unlocked — the map is 27 famous US cities and 36 famous parks and wonders (`docs/design_famous_places.md`) — once and reads it locally, so no map request ever names a place you've been (Decision 13). Never Google Maps — its terms forbid derivative map products.
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
Install **Godot 4.3** (stable, standard build — not .NET) from the official Godot site, and check the download against the release's `SHA512-SUMS.txt`. Open `game/project.godot` and press Play. With no revealed places the game shows the pairing screen; once a sync (or a demo import) has revealed places, it opens the map view. The map is built from Pokémon-style pieces over your real streets (slice 2), drawn with original placeholder tiles; the real Pokémon tiles arrive once you import your own Emerald ROM.

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
Route files (`.gpx`) of your real neighborhood, demo saves, and ROM dumps all live **outside** this repository. Never commit them — the repo is public.

## Status

Phases 0–1 (location capture, sync, persistence) are partly built and carry over unchanged. Everything Pokémon-specific is designed but not yet built. All `design_*.md` docs are contracts: implement exactly as specified, and file disagreements in `docs/ongoing_general_errors.md` as Decision blocks rather than silently deviating.
