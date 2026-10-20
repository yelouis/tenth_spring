# Story & World — The Backstory and Theme of Tenth Spring

This document is the **theme contract**. Every scene, line of text, quest, boss, item description, and design choice should fit the world described here. When a gameplay rule and the story disagree, file it in `ongoing_general_errors.md` rather than bending either quietly.

It was written on 2026-10-19 from the human's choices (Decision 18 and its follow-ups):
- the finale is a **stronger mirror of your own party**;
- it is combined with **nine regional Wardens**, so you must visit all nine US regions;
- the apocalypse/survival theme is **baked into both story and gameplay**;
- **Giratina is no longer the finale.**

**Content rules** (they apply to everything below):
- **Every name here is original.** Nothing comes from a Nintendo story — no existing characters, villain teams, professors, towns, or plot beats.
- **Pokémon are named for readability only.** Data refers to species by National Dex number, and names come from the player's ROM at runtime (`design_rom_asset_pipeline.md` §1).
- **Real public landmarks may be named** — national parks and monuments, for example. The player's own home, town, or streets never are (`agent_execution_guide.md`, standing constraint 5).
- **The phone companion carries none of this** — only its neutral scout vocabulary (`design_companion_and_sync.md` §1).

---

## 0. The pitch

Ten winters ago, a grey fog called **the Distortion** rose out of the places people had stopped visiting, and the country went still. Reality now holds only where someone still walks. The healing network went dark, the storage network went down, and the stores were left empty. Ghost Pokémon moved into everything people abandoned.

You are a **Walker** — one of the few whose footsteps keep the world real. On the first morning of the **tenth spring**, the fog around your home pulls back further than it has in ten years, everywhere you have walked. And something in the fog starts walking like you.

To stop it, you must earn the trust of the **nine Wardens** who hold the line across the United States, then face **the Echo**: the Distortion wearing your face and leading a stronger copy of your own team.

---

## 1. Theme — what every part of the game should feel like

| Theme | What it means | Where players feel it |
|---|---|---|
| **Presence holds the world** | Walking is an act of resistance. Places are real because someone goes there. | Real visits reveal the map; places you walk often are safer to explore; the fog stays wherever nobody walks. |
| **Absence becomes haunting** | The emptied world isn't evil — it's grieving. Ghost Pokémon are drawn to what people left behind. | Cemeteries, ruins, and abandoned hospitals teem with Ghosts; hauntings spread when ignored; night belongs to them. |
| **You have what you carry** | No shops, no healing network, no rescue. | Healing only at home; items are scavenged by searching real kinds of places; the bag drops where you black out; far from home you fight with the six you brought. |
| **Home is the anchor** | The one place that never fades is the place you always return to. | Full heal, the PC box, and the berry garden are home-only; blacking out wakes you at home; a haunting that reaches home seals the PC. |
| **The mirror** | The fog copies what crosses it, and it has been learning from you. | Distortion Fields copy other regions' Pokémon; the Echo's fragments wear familiar shapes; the finale is your own team, stronger. |
| **Hope at a distance** | Survivors are few and far apart, but they hold on. | Nine Wardens across the country; Waypost camps at the great landmarks; notes from other survivors found while scavenging. |

**Tone:** cozy tiles, quiet dread (`design_art_direction.md` §4). Melancholy but hopeful. The horror comes from **absence and wrongness** — a road that loops, a shop with its lights still on, footprints in the fog that match yours — never gore. Pokémon faint and are never killed. People "lost to the fog" are lost off-screen. Aim for the gentle-but-eerie register of the Ghost-type stories in the Pokémon games, and keep it suitable for the same audience.

---

## 2. Backstory — a timeline

### 2.1 Before: the Lit Years
The United States as we know it, with Pokémon living alongside people. Trainers travelled for fun. A national network of healing centres and linked storage terminals meant a trainer could heal or swap Pokémon in any town. Stores were stocked; roads were busy; the great national parks and monuments drew millions of visitors every year.

### 2.2 The Thinning
In the years before the collapse, people walked less. Deliveries came to the door, work moved onto screens, and whole places quietly emptied: malls closed, rail yards rusted, small towns lost their last diner. Nobody noticed that the emptiest places had begun to feel *thin* — compasses drifting, photographs coming out grey, Pokémon that didn't belong to the area wandering out of empty lots.

### 2.3 The Stillness — ten winters ago
One winter, the fog rose. It came first from the emptiest places — dead malls, closed factories, abandoned stations — and it spread along everything people had stopped using.

**Where the Distortion settled:**
- roads looped back on themselves;
- maps and photographs of the place came back blank;
- Pokémon from the other side of the country stepped out of it;
- people who walked in came back confused, or did not come back.

**It thickened where nobody walked and thinned where people did.** Fear kept people inside, and the empty streets fed it — a feedback loop. Within that one winter, most of the country went still.

**What failed, and why the game works the way it does:**
- **The healing network** drew on a grid that ran through the fog, and it went dark. *That is why full healing happens only at home.*
- **The linked storage network** went down. A trainer's boxes now live only on the old terminal they keep running at home. *That is why the PC box works only near home — the stranded rule.*
- **Supply chains** stopped. Shops still stand, half-stocked and overgrown. *That is why items are found by searching real places — pharmacies for medicine, hardware stores for Poké Balls.*
- **The League dissolved.** Gyms were abandoned, and their leaders scattered or were lost.

### 2.4 Who held on
The people who survived were the ones who kept walking: farmers, mail carriers, park rangers, pilgrims. **Wherever they walked, reality stayed firm.** The strongest ground of all was at the great landmarks — national parks and monuments, walked by millions for generations. Survivors gathered there and built **Waypost camps**, lamplit shelters strung along the old trails.

In each of the nine regions of the country, one person became the keeper of that region's firm places, travelling between its landmarks to keep the lamps lit. They are the **Wardens**. Each carries an **Anchor**: a stone taken from the firmest ground in their region, which the fog cannot copy.

### 2.5 The tenth spring — now
You grew up in the Stillness, in a house that never faded, because someone always walked it — first your family, then you. You learned what every survivor knows:
- be home before dark;
- carry what you need;
- never follow footprints into the fog.

On the first morning of the tenth spring, three things happen:
1. **The fog pulls back.** It recedes further than it has in ten years — along every street you have actually walked.
2. **A partner arrives.** A Pokémon wanders out of the receding fog into your garden and will not leave. It becomes your first partner. *(Proposed: a choice of three; dex numbers are fixed in the slice that builds the opening.)*
3. **Something walks like you.** At the edge of your lamplight that evening, a shape stands just as you stand, and moves when you move.

A survivor's note pinned to your door explains what the Wardens have long feared: **the Distortion is learning.** It has copied places and Pokémon for ten years. Now it is copying a person. The note says to find a Warden.

### 2.6 What "Walker" means in play
The phone companion is your **Ledger**. In the story it is the field journal every Walker keeps of where they have been. Your real walks are your character's scouting trips, and they reveal the world as **known** — grey silhouettes seen from the road. Going there *in the game* is what clears a place and lets you search it. The world remembers your footsteps, never your luggage: walking in real life reveals, it never gives (pillar 2).

---

## 3. The Distortion — rules of the world

**What it is.** Not a place, not a Pokémon, not a villain with a plan. The Distortion is a **hollow** — what is left of a place once nobody remembers walking it. It has no shape of its own, so it **copies whatever crosses it**:
- places — the stretches of roads, buildings, and grass it has absorbed;
- Pokémon — which is why Pokémon from the far side of the country can step out of a **Distortion Field**;
- and now, for the first time, **a person**.

**What it cannot copy:** legendary Pokémon, and the Wardens' Anchors. Both are *firm* by nature — anchors of reality in their own right. That is why legendaries never appear in Distortion Fields, and why the Anchors can pin the Echo down.

| In the story | In the game |
|---|---|
| Places hold where people walk | A real visit reveals a map cell (`known`); traveling there in-game clears it (`cleared`) — `design_world_generation.md` §1 |
| Unwalked places sink under the fog | `unknown` cells are impassable fog — the Distortion's shimmer (`design_art_direction.md` §3) |
| Ground you walk often is firmer | Familiarity: repeat real visits mean fewer encounters and pre-mapped interiors (`design_expeditions_and_survival.md` §3) |
| The healing network is dark | Full healing only at the home safehouse |
| The storage network is down | The PC box only within `baseAccessMeters` of home |
| The shops are empty | Items come only from searching places, by category (`design_resources_and_base.md` §1) |
| The fog takes what you carry | Blacking out drops the bag where you fell, recoverable for 3 game days |
| Your home is your anchor | After a blackout you wake at home, the party healed |
| Night belongs to the Ghosts | Ghost share ×3 at night, ×1.5 at dusk; a smaller light radius |
| Grief gathers and spreads | Haunted zones seed at cemeteries, ruins, and hospitals, and grow; at stage 4 next to home the Distortion jams the PC |
| Thin spots open and close | **Distortion Fields** (§6) |
| You move at walking pace | The 15 mph travel clock; the bicycle doubles it |
| Your body is the only door | Each session starts wherever your phone is; there is no other teleport |
| The Echo is learning you | Escalating Echo encounters, then the finale (§5) |

---

## 4. The nine regions and their Wardens

The country divides into the nine **US Census divisions** (Decision 18). Every state belongs to exactly one. **DC, Puerto Rico, and the US Virgin Islands count as South Atlantic** for the game.

**Trials (Decision 18 = B, trial location = any major landmark):**
- A Warden can be challenged at **any national park or national monument in their region** — they keep a Waypost camp at every one.
- The landmark must first be revealed by a real visit nearby, then reached in-game, as usual.
- Trials can be taken **in any order.**
- **Team levels scale with the Anchors you already hold:** level `22 + 6 × anchorsHeld`. So 22 for your first Warden and 70 for your ninth.
- **Each trial has a survival rule**, drawn from that region's hardship.
- Winning earns that Warden's **Anchor** — all nine are required for the finale — plus their part of the story and a small survival **perk**.

*The names, types, rules, and perks below are **starting content**: tunable, like the spawn tables, and built in the phase that implements trials.*

| Region (states) | Called | Landscape | Warden & specialty | Trial rule (survival twist) | Anchor perk (proposed) |
|---|---|---|---|---|---|
| **New England** (ME, NH, VT, MA, RI, CT) | the Lantern Coast | rocky shore, lighthouses, deep winters | **Maren Ashby** — Ice. A lighthouse keeper who never let her lamp go out. | **The Long Night** — fought after dark; no items may be used. | **Lamp:** night light radius +2 tiles |
| **Middle Atlantic** (NY, NJ, PA) | the Dead Grid | silent cities, bridges, rust | **Dex Ocampo** — Steel. A transit engineer who keeps one line of lights running. | **Brownout** — you may bring only 3 Pokémon. | **Salvage:** one extra item roll per site searched |
| **South Atlantic** (DE, MD, DC, VA, WV, NC, SC, GA, FL, PR, USVI) | the Green Tide | swamps, barrier islands, overgrown suburbs | **Lucía Reyes** — Grass. A botanist growing food in a reclaimed theme park. | **Rationing** — at most 2 healing items during the trial. | **Garden:** +2 berry plots |
| **East South Central** (KY, TN, MS, AL) | the Hollow Hills | caves, ridges, river towns | **Amos Whitlock** — Fighting. A retired miner who walks the ridges every day. | **The Climb** — two teams of 3, back to back, with no healing between. | **Pack:** a dropped bag lasts 5 game days instead of 3 |
| **West South Central** (AR, LA, OK, TX) | the Burnlands | heat, plains, bayou, dry riverbeds | **Rosa Tamez** — Fire. A wildfire crew chief who outran the fog twice. | **Drought** — harsh sunlight all battle. | **Hearth:** camping passes time with no ambush risk |
| **East North Central** (OH, IN, IL, MI, WI) | the Inland Seas | the Great Lakes, dunes, harbour towns | **Ingrid Halvorsen** — Water. Ferry captain of the last boat that still crosses. | **Storm Season** — rain all battle. | **Ford:** cross streams and small rivers on foot |
| **West North Central** (MN, IA, MO, ND, SD, NE, KS) | the Open Sky | prairie, badlands, storms | **Calla Brandt** — Flying. A storm-chaser who reads the fog like weather. | **Whiteout** — hail all battle. | **Wayfinder:** Distortion Fields show on the map from twice as far away |
| **Mountain** (MT, ID, WY, NV, UT, CO, AZ, NM) | the Ghost Frontier | deserts, canyons, mountain passes, ghost towns | **Silas Vance** — Ghost. Keeper of the ghost towns, at peace with what lives there. | **Fog Bank** — fog all battle (lowered accuracy). | **Ward:** hauntings near home grow one tick slower |
| **Pacific** (WA, OR, CA, AK, HI) | the Edge | redwoods, volcanoes, the long coast, islands | **June Okafor** — Psychic. The first Warden to understand that the Distortion copies. | **The Mirror** — her team includes copies of two of your Pokémon. A warning of what's coming. | **Sight:** landmarks within 50 miles hint "something stirs" if a legendary waits there |

**Why Wardens, not gyms:** the League is gone. The Wardens aren't testing whether you deserve a badge. They're testing whether you can survive what is coming. Each one gives you an Anchor because they believe you can carry it further than they can.

---

## 5. The Echo — the antagonist and the finale

**What it is.** The Distortion learning a shape. For ten years it copied places and Pokémon from the few people still walking. You walk more than anyone, so it is learning you: how you walk, which way you turn, the Pokémon you trust. It wants a shape of its own — and yours is the one it knows best.

**Why the Anchors matter.** The Echo is fog; you can't fight fog. Each Anchor is a piece of reality the Distortion cannot copy. Carry all nine to the place the Echo knows best, and it is forced into a single, solid shape — one that can be fought.

### 5.1 Escalation — the Echo grows with your Anchors
| Anchors held | What happens |
|---|---|
| 0–2 | Flavour only: a figure at the edge of your lamplight on night travel; footprints matching yours along the fog margin. |
| 3–5 | **Hollow Trainers:** on rare night encounters, a faceless trainer blocks your way with a copy of one of your Pokémon (level = your highest − 2). Beating one gives nothing — the fog gives nothing. |
| 6–8 | The Echo speaks in your words, quoting your own journal. Distortion Fields open more often (§6). |
| 9 | **The call.** The Echo takes your shape at the place you have visited most in real life — the revealed place with the highest real-world visit count. |

### 5.2 The finale — "The Last Walk"
- **Where:** your most-visited real place. If you start your session far from it, the trek there in-game is part of the finale. Your real body is still the only shortcut.
- **The battle:** the Echo leads an **exact mirror of your current party** — the same species, moves, abilities, natures, and held items — at **your levels + 5** (cap 100), with perfect IVs (31). It uses the strongest AI tier, and **no items** are allowed on either side.
- **Why a mirror:** you can't out-gear your own team, only out-think it. The finale rewards the team you built across the whole country, and every player's finale is different.
- **Blacking out** follows the normal rules — you wake at home and your bag lies where you fell. The Echo waits; you can return.

### 5.3 The ending
Defeated, the Echo loses the shape it stole and comes apart. The Distortion recedes from everywhere anyone has walked — **but not from the unwalked**. The fog remains wherever nobody goes. One battle doesn't save the world; walking does.

The credits roll over the Wardens' epilogues and your own map: every street you ever walked, lit.

**After the credits:**
- Distortion Fields keep opening — the Echo's leftover copies;
- haunted zones still grow;
- legendaries still wait at their landmarks.

*Proposed:* each new real-world spring, an "Eleventh Spring" rematch with a fresh Echo at your newest most-visited place.

---

## 6. Distortion Fields

**In the story:** thin spots where the Distortion's copies bleed through — a meadow that suddenly holds Pokémon from a desert two thousand miles away. Fields open, linger for a day, and close.

**In the game** (numbers and rules: `design_encounters_and_haunted_zones.md` §3a):
- **Any non-legendary species** can appear in a field, from any region.
- **Legendary and mythical Pokémon never appear in fields** — they can't be copied.
- Fields give a patient player who rarely travels a slow way to meet species from everywhere. **Travel stays the fast way, and the only way to the legendaries.**

---

## 7. Completing the Pokédex (Decision 18)

- **649 species.** The Pokédex is complete when every **non-legendary species is caught**, and every **legendary or mythical species is caught or defeated**.
- **Where species live:**
  - about a third live everywhere;
  - about 40% live only in certain **biomes** (desert, forest, coast, mountains, wetland, plains, snow, city);
  - about 20% live only in **one of the nine regions**;
  - the **legendary and mythical species** (about 48 in Generations 1–5) are each bound to the great landmarks of **one** region.
- **Distortion Fields** can bring any non-legendary species anywhere, slowly. **Legendaries require travel**, so the Pokédex can never be completed at home.
- **Legendaries are unique per save.** If one is defeated rather than caught, it still counts toward completion and returns after `legendaryRespawnGameDays = 30` for another catch attempt.
- **Starting assignments** — illustrative; the full table is `game/config/landmark_legendaries.json` (dex numbers and regions only), written in the slice that builds legendaries:

| Region | Examples |
|---|---|
| Lantern Coast (New England) | Articuno 144, Regice 378 |
| Dead Grid (Middle Atlantic) | Registeel 379, Genesect 649 |
| Green Tide (South Atlantic) | Lugia 249, Manaphy 490 |
| Hollow Hills (East South Central) | Regirock 377, Terrakion 639 |
| Burnlands (West South Central) | Moltres 146, Heatran 485 |
| Inland Seas (East North Central) | Uxie 480, Mesprit 481, Azelf 482 |
| Open Sky (West North Central) | Zapdos 145, Tornadus 641, Thundurus 642 |
| Ghost Frontier (Mountain) | Groudon 383, Giratina 487 |
| The Edge (Pacific) | Kyogre 382, Ho-Oh 250 |

---

## 8. Survival — the theme in every system

| System | Survival expression |
|---|---|
| Exploration | Every trip is a supply run, with daylight as the budget: the leave prompt shows the way home, daylight left, and party HP. |
| Healing | Home only. In the field, only what you found. |
| Items | Scavenged by category of real place; quality improves with distance and danger. The berry garden is the only renewable source. |
| Blackout | The fog takes your bag; you have 3 game days to get it back. |
| Night | Ghosts surge and light shrinks. Being caught out is the core danger. |
| Hauntings | The world pushes back toward home. Ignore it and lose your PC. |
| Travel | Distance is honest. Far from home, you have what you carry. |
| Wardens | Trials test survival — darkness, rationing, endurance, weather — not just levels. |
| The Echo | The last test: your own team, sharper. |
| Lore | Proposed: survivors' notes found while searching sites, collected in your journal. Original text only. |

---

## 9. Writing rules
- **Names:** original people and in-world names only. Real public places keep their real names. Never use the player's own home, town, or streets.
- **Voice:** plain, warm, a little weary. Survivors speak practically ("Back before dark."). The Echo speaks in the player's own words.
- **Never:** gore, on-screen deaths, cruelty to Pokémon, or mockery of real places or people.
- **The title:** "Tenth Spring" is the tenth spring since the Stillness — the season the fog first pulled back.
- **Open for later slices:** the full opening sequence, Waypost camp layouts and their survivors, survivors' notes, music and sound direction.
