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
| **Presence holds the world** | Walking is an act of resistance. Places are real because someone goes there. | Exploring in real life (Explore Here) reveals the map; places you explore on many days are safer; the fog stays wherever nobody goes. |
| **Absence becomes haunting** | The emptied world isn't evil — it's grieving. Ghost Pokémon are drawn to what people left behind. | Cemeteries, ruins, and abandoned hospitals teem with Ghosts; hauntings spread when ignored; night belongs to them. Half the houses have fallen in or vanished under grass, side streets are turning back into meadow, and only the great landmarks stand untouched. |
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
1. **The fog pulls back.** For the first time in ten years it lifts from the heart of the great city nearest home — the firm ground your family used to walk.
2. **A partner arrives.** A Pokémon wanders out of the receding fog into your garden and will not leave. It becomes your first partner. *(Proposed: a choice of three; dex numbers are fixed in the slice that builds the opening.)*
3. **Something walks like you.** At the edge of your lamplight that evening, a shape stands just as you stand, and moves when you move.

A survivor's note pinned to your door explains what the Wardens have long feared: **the Distortion is learning.** It has copied places and Pokémon for ten years. Now it is copying a person. The note says to find a Warden.

### 2.6 What "Walker" means in play
The phone companion is your **Ledger** — the field journal every Walker keeps. When you reach somewhere new in real life, you open it and press **Explore Here** to mark the ground as walked. That's what a Walker's footsteps do: the fog lifts from the whole neighbourhood, or the whole park. It shows as **known** — grey silhouettes seen from the road. Going there *in the game* is what clears a place and lets you search it. The world remembers your footsteps, never your luggage: exploring in real life reveals, it never gives (pillar 2).

**Distorting.** Since the Stillness, most of the country is fog. What still holds are the great cities and the great wild places, the ground walked by millions for generations (`design_famous_places.md`). A Walker can do one thing no one else can: **step through the Distortion** to firm ground they have walked themselves.
- **From home,** your safehouse, you can Distort to any famous place you've explored — and, from the first morning, to the great city nearest home, whose pull you've always felt.
- **The way back** opens only at a place's **Waypost**: the lamplit camp the survivors keep at its heart. So the old rule still holds — be back at the Waypost before dark.

---

## 3. The Distortion — rules of the world

**What it is.** Not a place, not a Pokémon, not a villain with a plan. The Distortion is a **hollow** — what is left of a place once nobody remembers walking it. It has no shape of its own, so it **copies whatever crosses it**:
- places — the stretches of roads, buildings, and grass it has absorbed;
- Pokémon — which is why Pokémon from the far side of the country can step out of a **Distortion Field**;
- and now, for the first time, **a person**.

**What it cannot copy:** legendary Pokémon, and the Wardens' Anchors. Both are *firm* by nature — anchors of reality in their own right. That is why legendaries never appear in Distortion Fields, and why the Anchors can pin the Echo down.

| In the story | In the game |
|---|---|
| Places hold where people walk | An Explore Here report reveals a neighbourhood or a whole park (`known`); traveling there in-game clears it (`cleared`) — `design_world_generation.md` §1–2 |
| Unwalked places sink under the fog | `unknown` cells are impassable fog — the Distortion's shimmer (`design_art_direction.md` §3) |
| Ground you walk often is firmer | Familiarity: exploring an area on more days means fewer encounters and pre-mapped interiors (`design_expeditions_and_survival.md` §3) |
| What's left untended falls | Ordinary buildings stand, lie ruined, or are gone; streets crack and grow over; only the landmarks and the blocks around each Waypost are kept (`implementation_plan_world_generation_slice2.md` §11) |
| The healing network is dark | Full healing only at the home safehouse |
| The storage network is down | The PC box only at home |
| The shops are empty | Items come only from searching places, by category (`design_resources_and_base.md` §1) |
| The fog takes what you carry | Blacking out drops the bag where you fell, recoverable for 3 game days |
| Your home is your anchor | After a blackout you wake at home, the party healed |
| Night belongs to the Ghosts | Ghost share ×3 at night, ×1.5 at dusk; a smaller light radius |
| Grief gathers and spreads | Haunted zones seed at cemeteries, ruins, and hospitals, and grow; at stage 4 next to home the Distortion jams the PC |
| Thin spots open and close | **Distortion Fields** (§6) |
| You move at walking pace | The 15 mph travel clock; the bicycle doubles it |
| Your footsteps open the doors | You can Distort only to famous places you've explored for real (plus the starter city) |
| The way home is at the Wayposts | You Distort home only from a place's Waypost, or by blacking out |
| The Echo is learning you | Escalating Echo encounters, then the finale (§5) |

---

### 3.1 What Calder learned — the fog's nine rules
Dr. Ruth Calder recorded the Distortion region by region before she vanished (`design_interiors_and_quests.md` §5.1). Each region's log names **one rule**, drawn from how that region went dark (§4a). Each rule explains a system the player already knows, so the lore and the game tell the same story.

| Region | Log | The rule | What it explains in play |
|---|---|---|---|
| New England | *The Unkept Lamps* | **Absence feeds it; presence starves it.** A place nobody walks thins, then fades, and a kept light holds it back. | Fog over unexplored places; Explore Here reveals; the night light radius; the lamps at every Waypost. |
| Middle Atlantic | *What Runs Through It* | **It drinks whatever runs through it** — power, signals, water. It started underground and climbed. | Why the healing and storage networks died, and why the PC works only at home; dark tunnels. |
| South Atlantic | *The Untended* | **It hides in what grows untended.** | Fallen houses and overgrown streets; tall grass as encounter ground; the berry garden stays safe because you tend it. |
| East South Central | *The Breathing Hills* | **It breathes.** Thin spots open and close like lungs. | Distortion Fields open, linger a day, and close. |
| West South Central | *Smoke Roads* | **It travels with what travels** — smoke, rivers, roads, and whatever you carry. | Pokémon from far regions in fields; the bag the fog takes when you black out. |
| East North Central | *The Ice Winter* | **It gathers where grief is**, and spreads from there when nobody tends it. | Haunted zones at cemeteries, ruins, and hospitals, and why they grow. |
| West North Central | *Reading the Sky* | **It behaves like weather:** it builds, it rolls, and it can be read. | Night surges; field forecasts (Calla's perk); weather in the Warden trials. |
| Mountain | *What Will Not Copy* | **It cannot copy what is firm** — the oldest ground, the legendary Pokémon, and stones from the firmest places. | Legendaries never appear in fields; each has one decisive battle; the Anchors pin the Echo. |
| Pacific | *The Echo* | **It copies what crosses it — and it has begun to copy a person.** | Hollow Trainers, the Echo, and the finale (§5). |

---

## 4. The nine regions and their Wardens

The country divides into the nine **US Census divisions** (Decision 18). Every state belongs to exactly one. **DC, Puerto Rico, and the US Virgin Islands count as South Atlantic** for the game.

**Trials (Decision 18 = B; refined 2026-10-20, Decision 26):**
- **A Warden appears only once all three of their region's famous cities are fully unlocked** — you've explored enough neighbourhoods in each, in real life (`design_famous_places.md` §3.2). They have been watching to see whether you can hold a whole region.
- **Each Warden waits at one fixed landmark** in one of the region's cities (`design_famous_places.md` §5).
- Trials can be taken **in any order.**
- **Every Warden fields a fixed level-75 team** (Decision 35), built like a competitive team and played to win, whenever you arrive. They are the strongest trainers left in the country, and they don't go easy on anyone. A Warden's ace can Mega Evolve (Decision 36).
- **Each trial has a survival rule**, drawn from that region's hardship.
- Winning earns that Warden's **Anchor** — all nine are required for the finale — plus their part of the story and a small survival **perk**.

*The names, types, rules, and perks below are **starting content**: tunable, like the spawn tables, and built in the phase that implements trials.*

| Region (states) | Called | Landscape | Warden & specialty | Trial rule (survival twist) | Anchor perk (proposed) |
|---|---|---|---|---|---|
| **New England** (ME, NH, VT, MA, RI, CT) | the Lantern Coast | rocky shore, lighthouses, deep winters | **Maren Ashby** — Ice. A lighthouse keeper who never let her lamp go out. | **The Long Night** — fought after dark; no items may be used. | **Lamp:** night light radius +2 tiles |
| **Middle Atlantic** (NY, NJ, PA) | the Dead Grid | silent cities, bridges, rust | **Dex Ocampo** — Steel. A transit engineer who keeps one line of lights running. | **Brownout** — you may bring only 3 Pokémon. | **Salvage:** one extra item roll per site searched |
| **South Atlantic** (DE, MD, DC, VA, WV, NC, SC, GA, FL, PR, USVI) | the Green Tide | swamps, barrier islands, overgrown suburbs | **Lucía Reyes** — Grass. A botanist growing food in Atlanta's botanical garden. | **Rationing** — at most 2 healing items during the trial. | **Garden:** +2 berry plots |
| **East South Central** (KY, TN, MS, AL) | the Hollow Hills | caves, ridges, river towns | **Amos Whitlock** — Fighting. A retired miner who walks the ridges every day. | **The Climb** — two teams of 3, back to back, with no healing between. | **Pack:** a dropped bag lasts 5 game days instead of 3 |
| **West South Central** (AR, LA, OK, TX) | the Burnlands | heat, plains, bayou, dry riverbeds | **Rosa Tamez** — Fire. A wildfire crew chief who outran the fog twice. | **Drought** — harsh sunlight all battle. | **Hearth:** camping passes time with no ambush risk |
| **East North Central** (OH, IN, IL, MI, WI) | the Inland Seas | the Great Lakes, dunes, harbour towns | **Ingrid Halvorsen** — Water. Ferry captain of the last boat that still crosses. | **Storm Season** — rain all battle. | **Ford:** cross streams and small rivers on foot |
| **West North Central** (MN, IA, MO, ND, SD, NE, KS) | the Open Sky | prairie, badlands, storms | **Calla Brandt** — Flying. A storm-chaser who reads the fog like weather. | **Whiteout** — hail all battle. | **Wayfinder:** Distortion Fields show on the map from twice as far away |
| **Mountain** (MT, ID, WY, NV, UT, CO, AZ, NM) | the Ghost Frontier | deserts, canyons, mountain passes, ghost towns | **Silas Vance** — Ghost. Keeper of the ghost towns, at peace with what lives there. | **Fog Bank** — fog all battle (lowered accuracy). | **Ward:** hauntings near home grow one tick slower |
| **Pacific** (WA, OR, CA, AK, HI) | the Edge | redwoods, volcanoes, the long coast, islands | **June Okafor** — Psychic. The first Warden to understand that the Distortion copies. | **The Mirror** — her team includes copies of two of your Pokémon. A warning of what's coming. | **Sight:** landmarks within 50 miles hint "something stirs" if a legendary waits there |

**Why Wardens, not gyms:** the League is gone. The Wardens aren't testing whether you deserve a badge. They're testing whether you can survive what is coming. Each one gives you an Anchor because they believe you can carry it further than they can.


### 4a. The regions' own stories

Each region went dark its own way. These are the survivors you meet there, and can battle, at the region's three cities. Their teams are fixed at level 50, and their "Old Friends" rematches after the region's Warden at level 80 (Decision 35). *The names and types are starting content, built in Phase 8.*

**New England — the Lantern Coast.**
- **How it went dark:** the fog came in off the Atlantic on the first night of a winter storm and never lifted. One by one the harbour lights went out, the ships stopped coming, and the coastal towns emptied inland. Ice Pokémon came down from the mountains into the empty streets.
- **Its Warden:** Maren Ashby kept Boston's harbour light burning by hand.
- **Survivors:**
  - **Boston** — Theo Marsh, a college rower who still runs the river every dawn (Water).
  - **Providence** — Iris Calloway, a glassblower who never lets her furnace go cold (Fire).
  - **Portland** — Ned Pruitt, an old lobsterman who never left the docks (Ice).

**Middle Atlantic — the Dead Grid.**
- **How it went dark:** it began underground. The subways and tunnels emptied first; the fog pooled there and rose through the grates. When the power grid failed in a cascade one January night, every city went dark at once. Steel and Electric Pokémon nest in the silent towers.
- **Its Warden:** Dex Ocampo keeps one line of lights running under Grand Central.
- **Survivors:**
  - **New York** — Priya Nandakumar, a subway musician whose songs keep the platform ghosts calm (Ghost).
  - **Philadelphia** — Benny Ruiz, a muralist who repaints the walls the fog fades (Normal).
  - **Pittsburgh** — Dorota Zielinski, a bridge inspector who still walks every bridge in the city (Steel).

**South Atlantic — the Green Tide.**
- **How it went dark:** here the fog came with the heat — a summer that never broke. Vines grew over everything people stopped tending, from highways to malls to whole suburbs, until the green was thicker than the fog. The coast flooded and was left to the sea.
- **Its Warden:** Lucía Reyes grows the food that feeds three cities.
- **Survivors:**
  - **Washington DC** — Marcus Bell, a museum guard who still makes his rounds through the empty galleries (Psychic).
  - **Atlanta** — Keisha Odom, a high-school coach who trains the neighbourhood kids (Fighting).
  - **Miami** — Rafael Duarte, a boat captain who navigates the flooded streets (Water).

**East South Central — the Hollow Hills.**
- **How it went dark:** the fog settled into the hollows and caves first, and the old mines breathed it out. River towns emptied as the water rose and nobody worked the locks. Rock and Fighting Pokémon roam the ridges.
- **Its Warden:** Amos Whitlock walks the riverbank at Memphis every day.
- **Survivors:**
  - **Nashville** — Lorraine Pike, a session fiddler who plays the empty stages every night (Normal).
  - **Memphis** — Darnell Hayes, a riverboat pilot (Water).
  - **Louisville** — Hank Abernathy, a stable hand who still exercises the racehorses' Pokémon (Fire).

**West South Central — the Burnlands.**
- **How it went dark:** drought came first, then wildfires, and the fog followed the smoke. Oil fields went quiet, and bayou towns sank back into the marsh. Fire and Ground Pokémon thrive in the heat.
- **Its Warden:** Rosa Tamez's crew still cuts firebreaks around Austin.
- **Survivors:**
  - **New Orleans** — Celestine Arceneaux, a trumpeter who leads a parade for the ghosts every Friday night (Ghost).
  - **Houston** — Dr. Amir Haddad, a former flight engineer who still tracks the stars (Psychic).
  - **Austin** — Jess Tran, a food-truck cook who feeds anyone who passes (Fire).

**East North Central — the Inland Seas.**
- **How it went dark:** the lakes froze one winter and never fully thawed, and the fog came across the ice. Factories fell silent, the ferries stopped, and the lakeshore towns emptied. Where the towns grieved most — their cemeteries and hospitals — the fog gathered thickest, and it has spread from there ever since. Water and Steel Pokémon haunt the harbours.
- **Its Warden:** Ingrid Halvorsen captains the last ferry on Lake Erie.
- **Survivors:**
  - **Chicago** — Mae Kowal, a train conductor who still walks the empty elevated tracks (Electric).
  - **Detroit** — Andre Moss, a mechanic who keeps old engines running (Steel).
  - **Cleveland** — Rosie Dombrowski, a radio DJ broadcasting to anyone left (Normal).

**West North Central — the Open Sky.**
- **How it went dark:** storms — year after year of storms so wild that people stayed in their cellars, and the prairie towns emptied one by one. The fog rolls across the plains like weather. Flying Pokémon ride the winds.
- **Its Warden:** Calla Brandt reads the fog from the roof of Kansas City's Union Station.
- **Survivors:**
  - **Minneapolis** — Siri Lindqvist, a snowplough driver who clears the same road every morning (Ice).
  - **St. Louis** — Calvin Brooks, a barge hand on the Mississippi (Water).
  - **Kansas City** — Rita Delgado, a pitmaster who keeps the smokehouse fires going (Fire).

**Mountain — the Ghost Frontier.**
- **How it went dark:** the old mining and boom towns had emptied long before the Stillness, so the fog found them first and spread along the highways. The desert cities lost their water and their lights — all but one. Las Vegas kept its lights, and the towns around it went dark faster than anywhere else in the country (§4b). Ghost Pokémon are everywhere, and calm — here they've had the longest to settle. And yet, after all that time, the canyons and caverns are still exactly themselves.
- **Its Warden:** Silas Vance keeps the Neon Boneyard in Las Vegas.
- **Survivors:**
  - **Las Vegas** — Lucky Morales, a retired stage magician (Psychic).
  - **Denver** — Hana Mori, a mountain-rescue volunteer (Rock).
  - **Phoenix** — Elena Ruiz, a hydrologist guarding the last canal water (Water).

**Pacific — the Edge.**
- **How it went dark:** the fog here was always natural — until it wasn't. One summer it rolled in off the ocean and kept coming, thicker each morning, until the coastal cities were islands in grey.
- **Its Warden:** June Okafor watched from Griffith Observatory and was the first to see that the fog copies what it touches.
- **Survivors:**
  - **San Francisco** — Kenji Watanabe, a cable-car gripman (Electric).
  - **Los Angeles** — Valentina Cruz, a stunt performer (Fighting).
  - **Seattle** — Nora Kittredge, a ferry deckhand (Water).

---

### 4b. The Glow — a pocket of order, and its price (Las Vegas, Decision 33)

**What it is.** Under the Fremont Street canopy in downtown Las Vegas, the lights never went out. When the Stillness came, the casino workers, performers, and regulars who stayed sealed the doors and kept the power on. Ten years later, **the Glow** is a working town, the only place in the country that still looks like the Lit Years:
- music every night and hot food;
- trade in **Glow chips**, the town's money;
- the **Glow Arena**, a battle hall with rules that change every day (`design_long_game.md` §4.7, if chosen).

**The House.** A council called the House runs the Glow, and its rules are simple: *everyone works, everyone plays, nobody leaves after dark, and the House keeps the lights on.*
- Chips are earned by work, by winning the House's **skill games** (logic and memory puzzles — the Glow never runs games of chance), or by winning in the Arena.
- The House's champion waits at the top of the STRAT tower, the Glow's beacon.

**The secret.** The Glow's power doesn't come from the dam or the sun.
- In the first winter, the House found something in the dark beneath Fremont Street: **Necrozma**, a creature made of hunger for light. The House built a vault of mirrors around it. Necrozma drinks light, and the mirrors bend what it drinks into power.
- To keep it fed, the mirrors pull light from across the desert. One by one the small desert towns' lamps dimmed and went out, and each town that went dark sank under the fog. **These are "the towns that went first"** (the Mountain Truth quest), and the Glow shone brighter with every one.

**Who knows:**
- **Silas Vance,** the Warden, keeps the Neon Boneyard as a quiet memorial: every sign in it came from a town the Glow drained.
- **Lucky Morales** suspects.
- **Elena Ruiz** in Phoenix has water and power records that don't add up.

**The player's path:**
1. Win in the Glow Arena and earn the House's trust.
2. Beat the House's skill games and its champion at the top of the STRAT tower.
3. **"The Light Bill":** find the House's ledger of drained towns.
4. Open the vault, and turn the mirrors back toward the desert. Each town relit opens a door.
5. Face Necrozma in its one decisive battle.

**After.** The Glow's lights dim to candlelight, but its people stay. They start walking their own streets, and that holds the fog better than stolen light ever did — Calder's first rule, that presence starves it (§3.1). The Arena reopens, lit by the Neon Museum's restored signs.

**Tone.**
- A pocket of order with a hidden cost.
- The House's people are survivors who made a bad bargain, not villains with a plan.
- Necrozma is freed, never punished, and nothing cruel happens on screen.
- The Glow is the first of what could become a pattern — a working town with a price — and later slices may add others.

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
| 9 | **The call.** The Echo takes your shape at the **famous place you've explored most in real life**: the most distinct days with an Explore Here report inside it, ties to the place explored first. |

### 5.2 The finale — "The Last Walk"
- **Where:** the famous place you've explored most in real life. You Distort there and walk from its Waypost to wherever the Echo stands; the walk is part of the finale.
- **The battle:** the Echo leads a **perfected mirror of your current party** — the same species, at **your levels + 5**, capped at 100.
  - **Level 100 is the cap,** so against a level-100 team the Echo's edge comes entirely from how its Pokémon are built (the human's rule, 2026-10-22):
    - **perfect IVs** — 31 in every stat;
    - **a competitive EV spread** for each species' role, using all 510 points;
    - the **nature, ability, held item, and four moves** a competitive player would choose for that species, from everything it can learn — not the moves you taught it.
  - It plays with the strongest AI tier, and **no bag items** are allowed on either side.
  - The builds come from the same rules as the Wardens' (`design_long_game.md` §4.3).
- **Why a perfected mirror:** it's your own team as a master would build it. You can't out-level it — at 100, nobody can — so you have to out-think it. The finale rewards the team you built across the whole country, and every player's finale is different.
- **Blacking out** follows the normal rules — you wake at home and your bag lies where you fell. The Echo waits; you can return.

### 5.3 The ending
Defeated, the Echo loses the shape it stole and comes apart. The Distortion recedes from everywhere anyone has walked — **but not from the unwalked**. The fog remains wherever nobody goes. One battle doesn't save the world; walking does.

The credits roll over the Wardens' epilogues and your own map: every neighbourhood you ever explored, lit.

**After the credits:**
- Distortion Fields keep opening — the Echo's leftover copies;
- haunted zones still grow;
- legendaries still wait at their landmarks.

*Proposed:* each new real-world spring, an "Eleventh Spring" rematch with a fresh Echo at your newest most-explored famous place.

---

## 6. Distortion Fields

**In the story:** thin spots where the Distortion's copies bleed through — a meadow that suddenly holds Pokémon from a desert two thousand miles away. Fields open, linger for a day, and close.

**In the game** (numbers and rules: `design_encounters_and_haunted_zones.md` §3a):
- **Any non-legendary species** can appear in a field, from any region.
- **Legendary and mythical Pokémon never appear in fields** — they can't be copied.
- Fields give a patient player who rarely travels a slow way to meet species from everywhere. **Travel stays the fast way, and the only way to the legendaries.**

---

## 7. Completing the Pokédex (Decision 18)

- **905 species** — Generations 1–8 (Decision 32). The Pokédex is complete when every **non-legendary species is caught**, and every **legendary or mythical species is caught or defeated**. The four that come only by evolution (Silvally, Cosmoem, Urshifu, Melmetal) count when obtained.
- **Where species live:**
  - about a third live everywhere;
  - about 40% live only in certain **biomes** (desert, forest, coast, mountains, wetland, plains, snow, city);
  - about 20% live only in **one of the nine regions**;
  - the **82 legendary and mythical species** wait at **78 famous places** of their own, themed to them and spread across all 9 regions;
  - the **11 Ultra Beasts** come only through Distortion Fields, after Necrozma is freed (`design_famous_places.md` §1.4).

  The full table of legendary places is `design_famous_places.md` §1.2.
- **Distortion Fields** can bring any non-legendary species anywhere, slowly. **Legendaries require travel**, so the Pokédex can never be completed at home.
- **One decisive battle per legendary** (Decision 26). Each waits behind a challenge — a maze or puzzle — and can be **caught or defeated once**; either ends it forever and counts for the Pokédex. Blacking out or running away doesn't use up the chance. Twenty have **lore requirements**, as in their legends — among them:
  - Lugia comes after the three birds, and Ho-Oh after the three beasts;
  - Rayquaza after Kyogre and Groudon, Giratina after Dialga and Palkia, and Kyurem after Reshiram and Zekrom;
  - Regigigas after the three Regis, and Keldeo after the three Swords;
  - Darkrai needs Cresselia's Moon Feather, and Shaymin comes only to a gardener;
  - Arceus needs all nine Anchors;
  - Eternatus needs the sword and the shield (Zacian and Zamazenta), Enamorus the three storm-spirits, and Calyrex a steed and a harvest;
  - Zygarde needs 50 of its 100 cells, found across the country.

  Every requirement is "caught or defeated", so no choice can lock a player out (`design_famous_places.md` §6).
- **Why one chance:** legendaries are anchors of reality, like the Wardens' stones. The Distortion can't copy them, and once one has been met, it has been *met*.

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
| Lore | **The Calder Logs** — nine field logs, one per region, each naming one of the fog's rules (§3.1) — plus the Lost Postcards and over 200 side quests that piece together what happened (`design_interiors_and_quests.md` §5, `content_quest_roster.md`). Collected in the Walker's Journal. Original text only. |

---

## 9. Writing rules
- **Names:** original people and in-world names only. Real public places keep their real names. Never use the player's own home, town, or streets.
- **Voice:** plain, warm, a little weary. Survivors speak practically ("Back before dark."). The Echo speaks in the player's own words.
- **Never:** gore, on-screen deaths, cruelty to Pokémon, or mockery of real places or people.
- **The title:** "Tenth Spring" is the tenth spring since the Stillness — the season the fog first pulled back.
- **Open for later slices:** the full opening sequence, Waypost camp layouts, the Calder Logs' full text, music and sound direction.
- **Dr. Ruth Calder** — the geographer who mapped the Thinning before the Stillness and recorded the fog's rules region by region before she vanished — is the thread tying the side quests to the main story (`design_interiors_and_quests.md` §5.1).
