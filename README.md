# Tenth Spring

A location-memoir survival game for **PC (Steam)** with a **phone companion app** (Android + iOS). The companion app passively tracks where you go in real life; that movement reveals a fog-of-war 2D overworld (Pokémon Diamond/Pearl-style pixel art) generated from your actual geography, which you then play on PC. Real life gives you **cartography, never cargo**: walking around only draws the map. All resources are earned by playing — sending your survivor across the in-game world, on foot at 15 mph, to raid the places you've unlocked.

**Platform split**: the PC game holds all gameplay — the overworld, raids, colonies, the base. The companion app is deliberately thin: location capture, a read-only map/memoir view, and sync. The payoff moment (fog peeling back, "3 places scouted") happens on PC, so sitting down to play feels like opening gathered intel.

Set a generation after the collapse: nature has swallowed the streets, the cities stand empty, and the dead still walk — by now organized into colonies.

**Working title cleared 2026-07-20** — no Steam/app-store/trademark collision found for "Tenth Spring" (domains + formal USPTO search still pending).

## Design Pillars (settled — do not re-litigate)

1. **Two-fog model** — a real visit turns a place Unknown → Known (grey silhouette). You must then travel there *in-game* to reach Cleared (raided).
2. **Cartography, never cargo** — real movement never yields resources.
3. **Intel, never inventory** — repeat real visits grant familiarity (pre-mapped interiors, lower raid risk), never loot.
4. **Fast travel = your real body** — your survivor starts each PC session wherever your *phone* is at sync time. Play at home → safehouse. Play on a laptop in another city → you spawn there. No other teleport exists.
5. **Stranded** — away from home you have only your carried inventory, never the base stash.
6. **Roguelite death** — dying drops your carried inventory at the death site (recoverable by a risky run). The map and all knowledge persist forever.
7. **The world pushes back** — zombies roam day *and* night; colonies grow, spread, and raid your base if ignored.
8. **Privacy is a pillar** — location processing on your own devices, home coordinates fuzzed, phone→PC sync is direct and end-to-end encrypted (no cloud relay of raw traces in v1.0). "Your map is yours."

## Documentation Map

| Doc | Contract |
|---|---|
| `docs/master_implementation_plan.md` | Phased build plan + core configuration constants |
| `docs/design_world_generation.md` | GPS → visits → OSM POIs → tile overworld pipeline |
| `docs/design_game_state_and_models.md` | Data models, schemas, on-device persistence |
| `docs/design_travel_and_time.md` | 15 mph rule, world clock, day/night, fast travel, stranded |
| `docs/design_companion_and_sync.md` | Companion app scope, pairing, phone→PC sync protocol |
| `docs/design_threats_and_colonies.md` | Zombie tiers, power scaling, colony lifecycle, base raids |
| `docs/design_expeditions_and_survival.md` | Raid loop, noise/stealth, familiarity effects, death & recovery |
| `docs/design_resources_and_base.md` | POI → resource mapping, fuel & vehicles, safehouse, crafting |
| `docs/design_art_direction.md` | Pixel-art spec, tile grid, palette, sprite sourcing pipeline |
| `docs/design_privacy_and_location.md` | Location permissions UX, on-device processing, fuzzing |
| `docs/agent_execution_guide.md` | How an engineering agent picks up this project |
| `docs/e2e_testing_journeys.md` | Manual end-to-end test journeys |
| `docs/ongoing_general_errors.md` | Engineering history, resolved issues, open decisions |

## Stack (Decision 0 — working assumption, revisit before Phase 1)

- **PC game: Godot 4** (Steam export, first-class 2D tilemaps/autotiling, pixel-perfect rendering). SQLite for saves; Steam Cloud optionally syncs the *game save*, never raw location traces.
- **Companion app: Flutter** (matches the Gaslight toolchain) — location capture + read-only map view + sync only. No gameplay.
- **Sync: direct device-to-device** over LAN (QR pairing, mDNS discovery, E2E-encrypted) — see `design_companion_and_sync.md`.
- **OpenStreetMap** (Overpass API) for POI categories and street geometry — IP-safe map data; queried by the PC, cached locally.
- **Background geolocation** on the phone via a battery-conscious significant-location-change strategy (see `design_privacy_and_location.md`).

## Status

Design phase. No code yet. All `design_*.md` docs are contracts: implement exactly as specified; file disagreements in `docs/ongoing_general_errors.md` as Decision blocks rather than silently deviating.
