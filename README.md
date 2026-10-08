# Tenth Spring

A Pokémon game in the Diamond/Pearl style where **your map is the places you have actually been.** A phone companion app passively records where you go in real life; that movement reveals a fog-covered overworld generated from your real geography, which you then explore on PC — catching Pokémon in main-series turn-based battles. Real life draws the map; everything on it is earned by playing.

**The setting:** a generation after a collapse. The streets are overgrown, the cities stand empty, and the Ghost types have moved in. The fog over the unexplored world is the Distortion — reality only holds where people still walk. Cemeteries, ruins, and abandoned hospitals are thick with Ghost Pokémon; at night they are everywhere. Hauntings spread outward if left alone. At the end, Giratina waits.

**How the Pokémon content works — read this first.** This is a non-commercial fan project. It contains **no Nintendo assets**. Like PokeMMO, the game asks you to import Pokémon ROMs **dumped from cartridges you own** — Pokémon Black or White, plus Platinum if you want the Diamond/Pearl-style sprites (pending Decision 10) — and reads sprites, species data, moves, and names from them on your own machine. All 649 Pokémon of Generations 1–5 are included. The project will never provide ROMs or help anyone find one. There is no Steam release, no sales, and no monetization. See `docs/design_rom_asset_pipeline.md`.

**Platform split:** the PC game holds all gameplay. The phone companion is deliberately thin — location capture, a read-only memoir map, and sync — and contains no Pokémon content at all.

## Design pillars (settled — do not re-litigate)

1. **Two-fog model** — a real visit turns a place Unknown → Known (grey silhouette). You must then travel there *in-game* to explore it.
2. **Real movement unlocks access, never cargo** — walking around never grants items or Pokémon. It reveals places, landmarks, and events, which must still be explored and won in play.
3. **Intel, never inventory** — places you visit often in real life are easier to explore in-game (pre-mapped interiors, fewer encounters), never richer.
4. **Fast travel = your real body** — each PC session starts wherever your *phone* is at sync time. No other teleport exists.
5. **Stranded** — your **PC box** is at home. Away from home you fight with the six you brought, and only home can fully heal them.
6. **Blackout drops the bag** — if your whole party faints you wake at home and your items stay where you fell, recoverable for a few days. Pokémon, the map, and the Pokédex are never lost.
7. **The world pushes back** — Ghost types own the night; hauntings spread from cemeteries and ruins and, ignored, will seal your PC.
8. **Privacy is a pillar** — location processing stays on your own devices, home coordinates are fuzzed, and phone→PC sync is direct and end-to-end encrypted. "Your map is yours."
9. **No Nintendo assets in this repository, ever** — the repo is public. ROMs and anything extracted from them live only on the player's machine.

## Documentation map

| Doc | Contract |
|---|---|
| `docs/agent_execution_guide.md` | **Start here** — how an engineering agent picks up this project |
| `docs/master_implementation_plan.md` | Phase order + tuning constants |
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
| `docs/implementation_plan_foundation.md` | Build steps for Phases 0–1 |
| `docs/e2e_testing_journeys.md` | Manual end-to-end test journeys |
| `docs/ongoing_general_errors.md` | Decisions, findings, engineering history |

## Stack

- **PC game: Godot 4.3.** SQLite for saves via the vendored `godot-sqlite` extension (Decisions 6–7). ROM import in pure GDScript.
- **Companion: Flutter** — location capture, read-only memoir map, sync. No gameplay, no Nintendo content.
- **Sync:** direct device-to-device over LAN — QR pairing, TLS with the PC's certificate pinned by the QR code (Decision 11), end-to-end encrypted.
- **Map data:** OpenStreetMap (Overpass API), queried by the PC and cached locally. Never Google Maps — its terms forbid derivative map products.
- **Distribution:** the asset-free client via GitHub Releases; the companion via the app stores.

## Setup notes

Configure git to use the repository's pre-commit hooks to ensure no prohibited ROM or Nintendo assets are committed:
```bash
git config core.hooksPath .githooks
```

## Status

Phases 0–1 (location capture, sync, persistence) are partly built and carry over unchanged. Everything Pokémon-specific is designed but not yet built. All `design_*.md` docs are contracts: implement exactly as specified, and file disagreements in `docs/ongoing_general_errors.md` as Decision blocks rather than silently deviating.
