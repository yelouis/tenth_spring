# The Long Game — Keeping Tenth Spring Challenging After Your Pokémon Get Strong

> **Status: decided 2026-10-22 (Decision 35, `ongoing_general_errors.md`).** The human asked: "In classic pokemon games, once you hit level 100, you are basically unstoppable. Since this game is so long, we don't want trainers with level 100 pokemon wiping out everybody they fight once they go to a new region/city. I also don't like the idea of having relative leveling systems where the Wardens are always stronger."
>
> After reading this brainstorm, they chose: **"I like the survival aspect and the mastery where each warden gets fixed level 75 competitive teams."**
>
> - §1 is the problem and §2 the principles.
> - §3 lists the fifteen ideas, marked chosen or not.
> - §4 is the chosen package, in buildable detail. It's built across Phases 5–8; nothing here is in the current agent guide items.

---

## 1. The problem
- **The journey is long and has no fixed order.** 27 cities, 78 legendaries, and 9 Wardens can be done in any order, over months of real travel. A team that reaches level 100 in month two would walk through everything after it.
- **The classic fixes don't fit:**
  - **fixed level curves** (gym 1 at 12, gym 8 at 50) assume a fixed order;
  - **relative scaling** (enemies grow with you) makes progress meaningless, and the human rejected it.
- **What must stay true:**
  - raising strong Pokémon still feels rewarding;
  - every fight has a difficulty you can know in advance;
  - far places stay dangerous because of where they are, not because of your level.

## 2. Principles
1. **Challenge comes from skill, preparation, and survival — not inflated numbers.**
2. **Fixed, not relative.** A battle is the same for every player whenever they arrive. Nothing reads your levels to decide how hard a fight is. The one exception is the Echo, whose whole idea — the human's choice in Decision 18 — is a stronger copy of you.
3. **Survival is the second difficulty axis.** A level-100 team that is worn out, out of PP, and far from home is still in danger.
4. **Strong Pokémon open doors** — legendary lairs, far regions, the deepest fog. They never make the world empty.

---

## 3. Fifteen ideas, and which were chosen

| # | Idea | How it works | Chosen? |
|---|---|---|---|
| 1 | **Fixed-level rules for named battles** ("Anchor Rules") | Every Pokémon in a Warden trial set to level 50 for that battle — the tournament format. | **No** — the human preferred fixed level-75 Wardens (#7) |
| 2 | **Obedience by Anchors** | Pokémon above `30 + 8 × anchorsHeld` may ignore orders. | **No** |
| 3 | **Scaled experience** | Experience shrinks when you out-level what you beat. | **Comes anyway** — Generation 8's own rules use it (Decision 32) |
| 4 | **Weariness** | Battles tire Pokémon; rest at home or a Waypost bed. | **Yes** — the survival half (§4.4) |
| 5 | **Distance tiers that keep rising** | Wild levels by real distance from home, extended to 65–85 across the country. | **Yes** — needed so a team can reach Warden strength by travelling (§4.2) |
| 6 | **Fog-swollen bosses** | Auras, a status-blocking veil, and two actions per turn below half health. | **Yes** (§4.5) |
| 7 | **Fixed, competitive named opponents** | Wardens at a fixed **level 75**, built like competitive teams, played by the strongest AI. | **Yes** — the mastery half (§4.1, §4.3) |
| 8 | **Regional conditions** | A standing weather or terrain per region. | Not decided — an idea for Phase 8 |
| 9 | **Inverted matchups in the deepest fog** | The type chart flips in stage-4 hauntings and deep fields. | **No** |
| 10 | **Variety formats** | Monotype, Little Cup, rentals, doubles. | At the Glow Arena only (§4.6) |
| 11 | **The Glow Arena** | Las Vegas's battle hall with rotating rules. | **Yes** — already part of the Glow (Decision 33) |
| 12 | **An honest Echo** | No +5. | **No** — the Echo stays a stronger mirror (Decision 18): +5 up to the level-100 cap, then stronger by build (§4.3) |
| 13 | **Fixed-level rematches** | Survivors and Wardens again, at fixed higher levels. | **Yes** (§4.1) |
| 14 | **Goals beyond levels** | The Pokédex, shinies, Zygarde cells, postcards, Mega Stones, the Eleventh Spring. | **Yes** — content already designed |
| 15 | **Optional hard modes** | "Ironwalker" rules. | Not decided — a later idea |

---

## 4. The chosen package — "Survival plus mastery"

### 4.1 Fixed levels for named battles — never relative
| Who | Level | Notes |
|---|---|---|
| **The nine Wardens** | **75** | The human's number. Replaces `22 + 6 × anchorsHeld`. |
| City survivors (27) | **50** | *Agent's reading:* same principle, mid-game. Replaces `18 + 6 × anchorsHeld`. |
| "Old Friends" rematches (after the region's Warden) | **80** | *Agent's reading.* |
| Warden rematches | **90** | *Agent's reading.* Each gives two Mega Stones (Decision 36). |
| The Echo | your levels **+ 5**, capped at **100** | The human's own "stronger mirror" (Decision 18). Level 100 is the cap, so at 100 the edge is the build: perfect IVs and competitive EVs, natures, abilities, items, and movesets (§4.3; the human, 2026-10-22). |

- The same numbers for every player, in any order. **All nine Wardens are equally hard;** they differ by type, survival rule, and style.
- **A level-75 Warden is a late goal.** A region's three cities unlock its Warden, but beating one takes a team raised by travelling — that is the "mastery".
- The *agent's reading* rows are starting values in `tuning.json`; the human may change them.

### 4.2 Wild levels keep rising across the country — amends `design_encounters_and_haunted_zones.md` §4

| Real distance from home | Wild level band |
|---|---|
| 0–2 mi | 2–10 |
| 2–10 mi | 8–22 |
| 10–50 mi | 18–38 |
| 50–300 mi | 30–50 |
| 300–1,000 mi | 42–62 |
| 1,000–2,000 mi | 55–75 |
| 2,000 mi or more | 65–85 |

- **Distance** runs from the starter city (home's famous city) to the place.
- Haunted pools keep their modifiers.
- The bands are fixed by geography, so they're the same for any player whatever their levels. The far side of the country stays a frontier — and it's where a team grows strong enough for the Wardens.

### 4.3 Smarter named opponents — and how a competitive build is made
- **Every Warden, survivor, and Arena team is written as a complete build:** species, moves, ability, held item, nature, and effort values.
- **The Echo's builds are generated** from the player's party at the moment of the finale, by the same rules (`game/battle/builds.gd`, Phase 8):
  - **role** from base stats: a physical attacker if Attack ≥ Special Attack + 10, a special attacker if the reverse, otherwise bulky;
  - **IVs** 31 in every stat;
  - **EVs** 252 / 252 / 4 — the attacking stat and Speed for an attacker, HP and the higher defence for a bulky Pokémon, the last 4 in HP or Speed;
  - **nature** raising the attacking stat (or Speed when the species is fast), and lowering the attacking stat it doesn't use;
  - **moves** from everything it can learn (level-up, TM, tutor): its two strongest same-type moves by power × accuracy; the coverage move that hits the most types its first two don't; and one status or setup move from a fixed list of move ids;
  - **ability and held item** from fixed per-role tables.
- **The builds are our own — never copied from Smogon's analyses,** which are copyrighted. Hand-authored teams (Wardens) use the same rules, then a human review.
- **They play with the strongest AI tier:** it switches out of bad matchups, uses setup moves, and predicts obvious attacks.
- **A Warden's ace can Mega Evolve** (Decision 36).
- This needs Phase 5's held items and trainer battles.

### 4.4 Weariness — the survival half
- **Stamina 0–100** per Pokémon, shown as a small bar beside HP.
- **Costs:** each battle a Pokémon takes part in costs 4; fainting costs 10 more.
- **Below 40 it is weary:** −1 Speed stage at the start of each battle. **At 0 it is exhausted** and can't be sent out.
- **Recovery:**
  - resting at **home** restores all of it;
  - a **Waypost camp bed** restores 50, once per game day per place;
  - a few rare scavenged items restore 25.
- **Why:** away from home you can't swap in fresh Pokémon (the stranded rule), so a long trip needs a plan — the survival game this world is about. With home-only healing and scarce PP, it means even a level-100 team has to be careful a thousand miles from home.
- Starting values live in `tuning.json`: `staminaMax = 100`, `staminaBattleCost = 4`, `staminaFaintCost = 10`, `staminaWearyBelow = 40`, `staminaWaypostBedRestore = 50`.

### 4.5 Fog-swollen Pokémon
- **Who:**
  - haunted-zone bosses at stage 3 or higher;
  - Pokémon in Distortion Fields that open after the player holds 6 or more Anchors;
  - the legendaries whose lair rows say so (Eternatus, for one — `design_interiors_and_quests.md` §4.3).
- **What they get:**
  - an aura of +1 to two stats;
  - a **veil** that blocks status conditions and stat drops until it takes three super-effective hits or loses half its HP;
  - **two actions per turn** below half HP.
- **Shown** with a grey shimmer and "Swollen" on the HP bar. Levels are unchanged — the challenge is the mechanics.

### 4.6 The Glow Arena — the endgame (`design_story_and_world.md` §4b)
- **Rules rotate each game day:**
  - open level;
  - fixed level 50 or 100;
  - Monotype;
  - Little Cup (first stages at level 5);
  - Rental (borrowed teams).
- **Win streaks of 7, 21, and 49** earn Glow chips, traded for TMs and rare items. Two Mega Stones come from 49-win streaks. **No betting, ever.**

### 4.7 What stays as it is
- the stranded rule;
- home-only healing;
- the bag drop on blackout;
- one decisive battle per legendary;
- Hollow Trainers — they copy you, at your highest level − 2, because copying is what the fog does.

### 4.8 Where this lands
**Already updated (2026-10-22):**
- `design_encounters_and_haunted_zones.md` §4 and §7.3;
- `design_creatures_and_battles.md` §11a (weariness) and §13a (Mega Evolution);
- `design_story_and_world.md` §4 and §4a;
- `design_famous_places.md` §5;
- `master_implementation_plan.md` tuning.

**Built across Phases 5–8.**
