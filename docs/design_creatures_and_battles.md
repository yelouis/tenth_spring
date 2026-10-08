# Creatures & Battles

This document defines the Pokémon model and the main-series battle system: stats, types, damage, status, catching, experience, party, PC box, healing, and blacking out. **The roster is all 649 Pokémon of Generations 1–5** (Decision 12). **Formulas follow Generation IV (Diamond/Pearl/Platinum); data comes from Black/White.** Formulas are game rules and live in the repo. Species data, move data, and names come only from the player's Black/White ROM, via `asset_db` (`design_rom_asset_pipeline.md` §2, §10). Gen 5 supplies data, never rules: no Gen 5 battle mechanics (critical captures, the Gen 5 EXP scaling, triple battles) are in scope.

Where a value below is marked **verify**, confirm it against Bulbapedia's Generation IV mechanics pages or `pret/pokeplatinum` before shipping — do not substitute a guess.

---

## 1. Species and instances

- **Species data** (base stats, types, catch rate, base EXP yield, growth rate, abilities, gender ratio, learnset, evolutions) is read from `asset_db.species(dex)`. The repo never stores it.
- **Instance data** (persisted in the save, `design_game_state_and_models.md`): `dex`, `level`, `exp`, `ivs[6]`, `evs[6]`, `nature`, `ability`, `gender`, `isShiny`, `moves[≤4]` with `pp`, `currentHp`, `status`, `caughtAtCell`, `caughtAtCategory`, `caughtAtGameDay`.
- **Wild generation:**
  - Level from the spawn band (`design_encounters_and_haunted_zones.md` §4).
  - Each IV uniform 0–31; nature uniform of 25; gender by species ratio; **shiny 1/8192**.
  - Ability uniform of the species' one or two **standard** abilities. Black/White data also lists a third, hidden ("Dream World") ability — **never assigned in v1**.
  - Moves = the last four level-up moves learned at or below the level.

## 2. Stats

- **HP** = ⌊(2·Base + IV + ⌊EV/4⌋) · Level / 100⌋ + Level + 10
- **Other** = ⌊(⌊(2·Base + IV + ⌊EV/4⌋) · Level / 100⌋ + 5) · Nature⌋, Nature ∈ {1.1, 1.0, 0.9}
- IVs 0–31. EVs 0–255 per stat, 510 total; each defeated Pokémon grants its species' EV yield.
- **Stat stages** −6…+6: multiplier `max(2, 2+s) / max(2, 2−s)`. Accuracy/evasion: `max(3, 3+s) / max(3, 3−s)`.

## 3. Types

- **17 types** (no Fairy — it did not exist in Gen IV). The full 17×17 chart is repo data at `game/config/type_chart.json`.
- Gen IV specifics that tests must assert: **Ghost has no effect on Normal**; **Normal and Fighting have no effect on Ghost**; Ghost is super-effective on Ghost and Psychic; Ghost is resisted by Dark **and by Steel** (Steel lost its Ghost/Dark resistance only in Gen VI — keep it). Dual-type effectiveness multiplies: 0, ¼, ½, 1, 2, 4.
- **Physical/special split is per move** (Gen IV introduced it) — read each move's category from move data, never derive it from type.

## 4. Battle flow (singles)

1. Each side chooses: Fight (move), Bag (item), Pokémon (switch), or Run (wild only).
2. Order: switches and items first; then moves by **priority bracket** (e.g. Shadow Sneak +1), then by effective Speed (stages applied; **paralysis ×0.25**); speed ties resolve randomly.
3. Resolve each action, then end-of-turn effects (status damage, Curse), then faint checks.
4. **Run** from wild battles uses the Gen IV escape formula (**verify**); never from boss or legendary encounters.

## 5. Damage

```
base   = ⌊⌊⌊2·L/5 + 2⌋ · Power · A / D⌋ / 50⌋
base  *= Burn        (0.5 if attacker burned and move is physical)
damage = (base + 2) · Crit · Random · STAB · Type1 · Type2 · AbilityMods
```
- `A`/`D` = Attack/Defense for physical moves, Sp. Atk/Sp. Def for special, with stages applied (crits ignore the attacker's negative and the defender's positive stages).
- **Crit:** stage 0 chance **1/16**; multiplier **×2** (×1.5 is Gen VI+ — don't use it).
- **Random:** uniform integer 85–100, ÷100. **STAB:** ×1.5. Floor after each multiplication; minimum 1 damage unless immune.
- Weather, held items, and doubles modifiers are **out of v1 scope** — leave explicit hook points, ×1.0 for now.

## 6. Status conditions (Gen IV)

| Status | Rule |
|---|---|
| Burn | 1/8 max HP at end of turn; halves physical damage |
| Poison | 1/8 max HP per turn. Toxic: n/16, n increments each turn, resets on switch |
| Paralysis | 25% chance to be fully paralyzed; Speed ×0.25 |
| Freeze | 20% thaw chance per turn; thaws if hit by a Fire move |
| Sleep | counter set on infliction, decremented per attempted move — **verify the Gen IV range** on Bulbapedia; implement as one tunable |
| Confusion | 1–4 turns; 50% self-hit (typeless 40-power physical) |
| Curse (Ghost-type user) | user loses ½ max HP; target loses ¼ max HP each turn until it switches |

## 7. Moves — v1 effect coverage

Move power, accuracy, PP, type, category, and **effect id** come from Black/White move data (559 moves). v1 implements the effect handlers below. Map Black/White's effect ids to them using Project Pokémon's Black move-data documentation, and record the mapping table in `game/config/move_effects.json` (effect ids → handler names only — repo-safe):
pure damage · secondary status chance (burn/poison/paralysis/sleep/freeze/confusion/flinch) · user/target stat stages ±1/±2 · heal 50% · drain 50% of damage · recoil (per-move fraction) · multi-hit 2–5 (37.5 / 37.5 / 12.5 / 12.5 %) · fixed damage equal to user level (**Night Shade**, Seismic Toss) · priority moves (**Shadow Sneak**) · Ghost-type **Curse**.
**Any unimplemented effect falls back to damage-only and logs its effect id once.** Never silently skip it.

## 8. Abilities — v1 subset

**Levitate** (Ground immunity — common among ghosts) · **Wonder Guard** (only super-effective hits land) · **Pressure** (opponent's moves cost 2 PP) · **Insomnia** (sleep immunity) · **Overgrow / Blaze / Torrent / Swarm** (×1.5 to matching-type moves at ≤ ⅓ HP) · **Cursed Body** (Frillish/Jellicent: 30% chance to disable the move that hit it for 4 turns) · **Mummy** (Cofagrigus: a contact move's attacker has its ability replaced by Mummy). All others: no effect, logged once per ability id.

## 9. Catching (Gen III–IV formula)

```
a = ⌊(3·HPmax − 2·HPcur) · CatchRate · Ball / (3·HPmax)⌋ · Status
if a ≥ 255 → caught
b = ⌊1048560 / ⌊√⌊√⌊16711680 / a⌋⌋⌋⌋
four shake checks: each draws uniform 0–65535; all four < b → caught
```
- **Status:** sleep/freeze ×2; paralysis/poison/burn ×1.5.
- **Balls:** Poké ×1 · Great ×1.5 · Ultra ×2 · **Dusk ×3.5 at night or inside haunted interiors** (Gen IV value; the signature ball of this setting) · Quick ×4 on turn 1 · Master: always.
- Legendaries and zone bosses use their species catch rate (often 3) — no special-casing.

## 10. Experience, levels, evolution

- **EXP per defeated Pokémon:** `⌊(a · b · L) / (7 · s)⌋` — `a` = 1 wild / 1.5 boss, `b` = base EXP yield, `L` = defeated level, `s` = number of participants.
- **Growth curves** — the six Gen III–IV curves, encoded in repo. Unit tests assert the level-100 totals: Erratic **600,000** · Fast **800,000** · Medium Fast **1,000,000** · Medium Slow **1,059,860** · Slow **1,250,000** · Fluctuating **1,640,000**.
- **Evolution v1:** level-up and evolution stones (including **Dusk Stone** — Misdreavus → Mismagius, Murkrow → Honchkrow, Lampent → Chandelure). Other methods (friendship, trade, held item, location) are read from the ROM, shown as "a condition you haven't met," and logged as unsupported.
- **Learning moves on level-up:** if four moves are known, prompt to replace one or skip.

## 11. Party, PC box, healing, blacking out

- **Party: 6.** It travels with the player.
- **PC box** lives at the **home safehouse**. Catching with a full party deposits remotely — that always works — but **withdrawing or swapping is only possible within `baseAccessMeters` of home**. This *is* the stranded rule (`design_travel_and_time.md` §5): far from home, you fight with the six you brought.
- **No Pokémon Centers** — the world collapsed. **Full healing happens only at the home safehouse.** In the field, healing comes from bag items (Potions, Antidotes, Revives — scavenged, `design_resources_and_base.md`). Scarce healing is the survival undertone.
- **Blacking out** (all party Pokémon fainted): wake at home with the party fully healed. **The bag's contents drop at the tile where you blacked out**, recoverable for `bagCacheDecayGameDays = 3`. Pokémon are **never** lost; the map, Pokédex, and PC always persist.

## 12. Opponent behavior

- **Wild:** uniformly random among moves with PP.
- **Zone bosses and legendaries:** weighted — super-effective moves ×2, not-very-effective ×0.5, moves the target is immune to ×0. Bosses never Run.

## 13. Pokédex — the memoir

Seen/caught per National Dex number. Each caught entry records the **real place category and cell** where it was first caught and the game day. Over a year, the Pokédex becomes a record of where the player actually went. Store categories and cells only — never coordinates.

## 14. Out of scope for v1 (do not build)
Double battles · trainer battles (survivor trainers are a later phase) · held items in battle · weather · breeding · trading · online play (see Decision 8).

## 15. Files
* `game/creatures/pokemon.gd` (instance), `game/creatures/stats.gd`, `game/creatures/growth.gd`
* `game/battle/engine.gd` (turn loop), `game/battle/damage.gd`, `game/battle/status.gd`, `game/battle/effects/*.gd`, `game/battle/abilities.gd`, `game/battle/catch.gd`, `game/battle/ai.gd`
* `game/config/type_chart.json` — the Gen IV 17×17 chart (mechanics data, repo-safe)
