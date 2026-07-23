# Travel, Time & Fast Travel

This document defines the world clock, the 15 mph travel economy, day/night, physical-presence fast travel, and the stranded rule. The pillar: **in-game distance is expensive; the only teleporter is your real body.**

## 1. The World Clock

- Simulation time advances only while the app is open: `wallSecondsPerGameMinute = 2.0` (one in-game day ≈ 48 wall minutes; tunable).
- Time-of-day bands: **dawn** 05–07, **day** 07–19, **dusk** 19–21, **night** 21–05. Night applies the danger multipliers in `design_threats_and_colonies.md` §3 and shrinks light radius on-screen.
- On app resume, the clock does *not* fast-forward (no punishing returning players) — except colony growth catch-up (max 3 ticks, see models doc §1).

## 2. The Travel Economy (15 mph Rule)

- The survivor covers **real geographic distance** at `walkSpeedMph = 15` → `gameMinutesPerMile = 4`.
- **Authority**: travel *time* is simulation-authoritative. On-screen tile movement is aesthetic; when the player walks a route, the world clock is charged `realMiles × 4` game-minutes for the distance covered, pro-rated continuously.
- **UI speaks in time, not distance**: every destination chip shows travel time — "Elm St. pharmacy — 38 min on foot" — and paints it against remaining daylight (green = round trip before dusk, amber = one-way only, red = you'll be out at night).
- **Vehicles** divide travel time by their speed factor and burn fuel per real mile (`design_resources_and_base.md` §3). Fuel = reach.
- **Encounter pressure scales with distance**: encounter rolls are made per game-minute traveled, so a 90-minute trek is intrinsically riskier than a 10-minute one. No random encounters inside a 3-minute home radius (the "porch").

## 3. Route & Movement Rules

- Overworld movement is free-walk on revealed tiles (D/P grid movement, camera-follow). Fogged (`unknown`) tiles are impassable walls of black; `known` grey tiles are traversable but muted, with silhouette buildings un-enterable until cleared... clearing requires arriving and raiding (`design_expeditions_and_survival.md`).
- Roads are fast terrain (×1.0 speed), wilderness ×0.7, colony territory ×0.7 with forced encounter rolls.
- **Nightfall on the road**: being outside the porch at night doesn't teleport-punish; it just makes the trek home genuinely dangerous. Camping items can pass time in place at an ambush risk.

## 4. Fast Travel = Your Real Body (Anchored by the Phone)

- Gameplay is on PC, so the survivor's body is anchored to the **phone**: on every PC session start, the game syncs with the companion and receives a `bodyFix` (the phone's current fuzzed position — `design_companion_and_sync.md` §3). The survivor spawns there, snapped to the nearest revealed traversable tile; if the area is `unknown`, a minimal `known` circle of `corridorRevealMeters` is granted so there's ground to stand on.
- Playing at home (phone in your pocket at your desk) → you spawn at the safehouse. Playing on a laptop in a hotel 200 miles away → you spawn in that city, stranded.
- If the phone is unreachable at launch, the session starts at the **last synced body position** with a "scout out of contact" banner — never blocked, never teleported home.
- This is the *only* teleport in the game. There is no in-game fast travel between islands, ever.
- Relocation is not punished — but it triggers the **stranded rule**.

## 5. The Stranded Rule

- The base stash is accessible only within `baseAccessMeters` (500 m, tunable) of the safehouse. Everywhere else, the survivor has exactly what `carried` holds. This radius is a game constant, separate from the `homeFuzzMeters` privacy fuzz.
- Starting a session far from home = arriving with what's on your back: scavenge locally, survive, and either trek home in-game (honest 15 mph across the full real distance, with fuel logistics for far islands) or physically return home and start a session there (fast travel).
- Session-start banner states it plainly: *"You are 212 miles from home. You have what you carry."*

## 6. Files (PC game)
* `game/systems/world_clock` — tick, bands, daylight budget helpers.
* `game/systems/travel` — route timing, terrain factors, encounter pressure.
* `game/systems/relocation` — session-start `bodyFix` spawn + stranded banner.
