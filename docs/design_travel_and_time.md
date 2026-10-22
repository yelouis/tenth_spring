# Travel, Time & Fast Travel

This document defines the world clock, the 15 mph travel economy, day/night, physical-presence fast travel, and the stranded rule. The pillar: **in-game distance is expensive; the only teleporter is your real body.**

## 1. The World Clock

- Simulation time advances only while the app is open: `wallSecondsPerGameMinute = 2.0` (one in-game day ≈ 48 wall minutes; tunable).
- Time-of-day bands: **dawn** 05–07, **day** 07–19, **dusk** 19–21, **night** 21–05. Night triples the ghost share of wild encounters and dusk raises it ×1.5 (`design_encounters_and_haunted_zones.md` §3); night also shrinks the on-screen light radius. Night is when the Ghost types own the world.
- On app resume, the clock does *not* fast-forward (no punishing returning players) — except haunting growth catch-up (max 3 ticks, see models doc §1).

## 2. The Travel Economy (15 mph Rule)

- The player covers **real geographic distance** at `walkSpeedMph = 15` → `gameMinutesPerMile = 4`.
- **Authority**: travel *time* is simulation-authoritative. On-screen tile movement is aesthetic; when the player walks a route, the world clock is charged `realMiles × 4` game-minutes for the distance covered, pro-rated continuously.
- **UI speaks in time, not distance**: every destination chip shows travel time — "Elm St. pharmacy — 38 min on foot" — and paints it against remaining daylight (green = round trip before dusk, amber = one-way only, red = you'll be out at night).
- **Bicycle** (key item, `design_resources_and_base.md` §4) halves travel time. There is no fuel and no other vehicle.
- **Encounter pressure scales with distance**: encounter rolls are made per game-minute traveled, so a 90-minute trek is intrinsically riskier than a 10-minute one. No random encounters inside a 3-minute home radius (the "porch").

## 3. Route & Movement Rules

- Overworld movement is free-walk on revealed tiles (D/P grid movement, camera-follow). Fogged (`unknown`) tiles are impassable walls of black; `known` grey tiles are traversable but muted, with silhouette buildings un-enterable until the player arrives in-game and explores them (`design_expeditions_and_survival.md`).
- Roads are fast terrain (×1.0 speed), wilderness ×0.7, tall grass ×0.8 (and rolls encounters per step), haunted territory ×0.7.
- **Nightfall on the road**: being outside the porch at night doesn't teleport-punish; it just makes the trek home genuinely dangerous. Camping items can pass time in place at an ambush risk.

## 4. Distort — Travel Between Famous Places (Decision 25, 2026-10-20)

*(Viewer level built in Item 20: `home_hub.tscn`, `town_map.tscn`, Waypost `Return home` button, camera 1-cell tracking, and `main.gd` boot routing. Full walking avatar, session-start banner, and game clock arrive in Phase 4).*

The map contains only famous places (`design_famous_places.md`), so there's nothing to walk across between them. Your real body still decides where you can go; the Distortion carries you there.

- **From home,** Distort for free to any famous place you've physically visited (any recorded movement inside it), plus your **starter city** — the famous city nearest your fuzzed home. You arrive at the place's **Waypost**: city hall for cities, the main visitor centre for parks and wonders.
- **Back home: only from that place's Waypost** — or by blacking out.
- **Between places:** go through home.
- **Distort costs no game time** and is never blocked by night. The world clock pauses at home, as when the game is closed.
- **Session start:** the game syncs with the companion for a `bodyFix` (`design_companion_and_sync.md` §3).
  - If the fix lies inside a famous place, you start there, snapped to the nearest revealed traversable tile, and that place unlocks.
  - Otherwise you start at home.
  - If the phone is unreachable, you start where the last session ended, with a "scout out of contact" banner.
- **This replaces "your real body is the only teleport."** Distort is the one teleport. It goes only where your body has been, and only from home.

## 5. The Stranded Rule

- **The PC box and full healing are at home only.** In any famous place you fight with the party and bag you brought (newly caught Pokémon still deposit remotely).
- **Getting home** means walking back to the place's Waypost — honest 15 mph, 30 by bicycle — before your party or the daylight runs out, or blacking out and losing your bag where you fell.
- **The session-start banner states it plainly:** *"You are in <place>. The Waypost is 38 min on foot. You have what you carry."*

## 6. Files (PC game)
* `game/systems/world_clock` — tick, bands, daylight budget helpers.
* `game/systems/travel` — route timing, terrain factors, encounter pressure.
* `game/systems/relocation` — session-start `bodyFix` spawn + stranded banner.
* `game/systems/distort` — the Distort list, Waypost arrival and departure, the home hub.
