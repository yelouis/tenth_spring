# Famous Places — What the Map Contains, How It Unlocks, Distort Travel, and the Same Map for Everyone

This is the contract for the map's scope. It was decided by the human on 2026-10-20 (Decisions 21–26 in `ongoing_general_errors.md`), narrowing "the whole USA" to **famous places only, for now**.

Public places are named here by their real names. **The human's own home, town, and starter city are never named in this repo** (agent guide, standing constraint 5).

---

## 0. In one paragraph
The map is made of islands: **27 famous US cities** and **36 famous parks, monuments, and natural wonders**. Everything else is fog. Your home is not on the map — it's your safehouse hub, where you heal, keep your PC box, tend your garden, and **Distort** (step through the fog) to any place you have physically visited. On day one, the famous city nearest your home is open to you for free. You arrive at each place's **Waypost**, and you can only Distort home from there.

Inside a city, passing through a neighbourhood in real life reveals it; enough neighbourhoods reveal the whole city. Visiting any part of a park reveals all of it.

Each region's **Warden** waits at one landmark, once you've unlocked all three of that region's cities. Each of the **48 legendary Pokémon** waits at its own themed place, behind a challenge, for one decisive battle.

---

## 1. What exists on the map

### 1.1 The 27 famous cities (3 per region)
| Region | Cities |
|---|---|
| New England | Boston · Providence · Portland (Maine) |
| Middle Atlantic | New York · Philadelphia · Pittsburgh |
| South Atlantic | Washington DC · Atlanta · Miami |
| East South Central | Nashville · Memphis · Louisville |
| West South Central | New Orleans · Houston · Austin |
| East North Central | Chicago · Detroit · Cleveland |
| West North Central | Minneapolis · St. Louis · Kansas City |
| Mountain | Las Vegas · Denver · Phoenix |
| Pacific | San Francisco · Los Angeles · Seattle |

- **A city's extent** is its official boundary (city limits) in OpenStreetMap, identified by a fixed relation id in `game/config/famous_places.json` (§9).
- **Its Waypost** is its **city hall**.

### 1.2 The 48 legendary places — one legendary each, never two in one spot
Every legendary and mythical species of Generations 1–5 has its own place, themed to it and spread across the regions (5–6 per region).
- Places marked **(city)** are a landmark inside one of the 27 cities.
- The other **36** are islands of their own, with a Waypost at their main visitor centre (or main entrance, where there is none).

| Region | Dex | Legendary | Place | Why it fits |
|---|---|---|---|---|
| New England | 144 | Articuno | Acadia National Park (ME) | the icy North Atlantic coast |
| New England | 378 | Regice | Mount Washington State Park (NH) | the summit famous for record cold and rime ice |
| New England | 481 | Mesprit | Walden Pond State Reservation (MA) | a pond known for reflection and feeling |
| New England | 489 | Phione | Cape Cod National Seashore (MA) | drifting tide pools and dunes |
| New England | 491 | Darkrai | Salem Maritime National Historical Park (MA) | a town famous for its spooky legends |
| Middle Atlantic | 379 | Registeel | Hot Metal Bridge, Pittsburgh **(city)** | the Steel City |
| Middle Atlantic | 385 | Jirachi | Statue of Liberty, New York **(city)** | a monument to wishes and hope |
| Middle Atlantic | 482 | Azelf | Niagara Falls State Park (NY) | willpower against the falls |
| Middle Atlantic | 494 | Victini | Independence Hall, Philadelphia **(city)** | victory and independence |
| Middle Atlantic | 644 | Zekrom | Thomas Edison National Historical Park (NJ) | electricity and an inventor's ideals |
| South Atlantic | 151 | Mew | Great Smoky Mountains National Park (NC/TN) | one of the most biodiverse places in the country |
| South Atlantic | 249 | Lugia | Cape Hatteras National Seashore (NC) | storms and deep water off a lighthouse coast |
| South Atlantic | 384 | Rayquaza | Wright Brothers National Memorial (NC) | the birthplace of flight |
| South Atlantic | 490 | Manaphy | Biscayne National Park (FL) | coral reefs and the open sea |
| South Atlantic | 638 | Cobalion | Lincoln Memorial, Washington DC **(city)** | justice |
| East South Central | 243 | Raikou | Waterfront Park, Louisville **(city)** | the riverfront famous for "Thunder" fireworks |
| East South Central | 377 | Regirock | Russell Cave National Monument (AL) | an ancient rock shelter |
| East South Central | 383 | Groudon | Reelfoot Lake State Park (TN) | a lake made when earthquakes reshaped the land |
| East South Central | 639 | Terrakion | Mammoth Cave National Park (KY) | the world's longest cave system |
| East South Central | 648 | Meloetta | Ryman Auditorium, Nashville **(city)** | Music City |
| West South Central | 146 | Moltres | Big Bend National Park (TX) | desert heat |
| West South Central | 244 | Entei | Hot Springs National Park (AR) | water heated deep in the earth |
| West South Central | 382 | Kyogre | Padre Island National Seashore (TX) | the open Gulf |
| West South Central | 386 | Deoxys | Space Center Houston **(city)** | spaceflight |
| West South Central | 640 | Virizion | Buffalo National River (AR) | Ozark forests |
| East North Central | 245 | Suicune | Cuyahoga Valley National Park (OH) | a river famously brought back clean |
| East North Central | 480 | Uxie | Isle Royale National Park (MI) | a remote island on Lake Superior |
| East North Central | 486 | Regigigas | Sleeping Bear Dunes National Lakeshore (MI) | a "sleeping" giant |
| East North Central | 641 | Tornadus | Northerly Island lakefront, Chicago **(city)** | the Windy City |
| East North Central | 649 | Genesect | Michigan Central Station, Detroit **(city)** | the Motor City's great machine hall |
| West North Central | 145 | Zapdos | Theodore Roosevelt National Park (ND) | lightning over the badlands |
| West North Central | 380 | Latias | Bde Maka Ska (Chain of Lakes), Minneapolis **(city)** | one of the Twin Cities' lakes |
| West North Central | 381 | Latios | Voyageurs National Park (MN) | lakes and islands to the north |
| West North Central | 493 | Arceus | Gateway Arch, St. Louis **(city)** | the gateway — the "Alpha" monument |
| West North Central | 642 | Thundurus | Badlands National Park (SD) | prairie thunderstorms |
| West North Central | 645 | Landorus | Tallgrass Prairie National Preserve (KS) | land and harvest |
| Mountain | 250 | Ho-Oh | Yellowstone National Park (WY) | the rainbow colours of Grand Prismatic Spring |
| Mountain | 483 | Dialga | Grand Canyon National Park (AZ) | two billion years of time in the rock |
| Mountain | 484 | Palkia | Arches National Park (UT) | gaps opened in space |
| Mountain | 487 | Giratina | Carlsbad Caverns National Park (NM) | a hidden world below |
| Mountain | 488 | Cresselia | Craters of the Moon National Monument (ID) | a moonscape |
| Mountain | 643 | Reshiram | White Sands National Park (NM) | white dunes |
| Pacific | 150 | Mewtwo | Alcatraz Island, San Francisco **(city)** | escape from a cell built to hold anything |
| Pacific | 251 | Celebi | Redwood National Park (CA) | ancient forest — time |
| Pacific | 485 | Heatran | Hawaiʻi Volcanoes National Park (HI) | living lava |
| Pacific | 492 | Shaymin | Mount Rainier National Park (WA) | wildflower meadows |
| Pacific | 646 | Kyurem | Glacier Bay National Park (AK) | ice |
| Pacific | 647 | Keldeo | Yosemite National Park (CA) | waterfalls |

*The species, places, and themes are starting content, like the spawn tables. The human may swap any row; keep the rule "one legendary per place".*

### 1.3 Everything else
Not on the map, for now. Cells outside every famous place are never drawn and never offered for download, even if the phone was there. The phone still records them, and the save still stores them (golden invariants unchanged), so widening the scope later loses nothing.

---

## 2. Home — the hub
- **Home is not on the map.** It's a hub screen: your house, with **full healing**, the **PC box**, the **berry garden**, and the **Distort door**.
- **The real home location** is designated once during onboarding, fuzzed per `design_privacy_and_location.md`, and used for one thing only: choosing the **starter city** (§3.1). It never leaves the PC.
- **The stranded rule becomes:** away from home, in any place, you have only the party and bag you brought. Healing and the PC box are at home. You get home only through a Waypost (§4) — or by blacking out.

---

## 3. Unlocking
**"Visiting" always means real movement recorded by the phone** — any visit or passing-through point, after fuzzing. In-game travel never unlocks a place; it only clears it, under the two-fog model.

### 3.1 The starter city
On day one, the famous city whose Waypost is nearest the fuzzed home — by ground distance, ties to the lower place id — is on your Distort list. Its **Waypost neighbourhood** is revealed (`known`), so you have ground to explore. The rest of it opens as you visit for real.

### 3.2 Cities: neighbourhoods, then the whole city
- **Neighbourhoods** come from OpenStreetMap inside the city's boundary: named `admin_level` 9/10 areas, else the nearest `place=neighbourhood|suburb|quarter` node, else 4 × 4-cell districts (`implementation_plan_famous_places.md`).
- **Any real movement inside a neighbourhood reveals all of it** (Decision 21 = B).
- **The whole city is revealed** once `T` of its neighbourhoods are: `T = 1` if the city has 1 neighbourhood, else `clamp(ceil(0.10 × n), 2, 5)` (Decision 22 = A).
- **The first real movement anywhere in a city** also puts it on your Distort list.

### 3.3 Legendary places outside cities
Any real movement anywhere inside the place's boundary reveals the **whole place** and puts it on your Distort list.

### 3.4 Unlocking only ever adds
Nothing is ever re-locked, and reveal states never decrease.

---

## 4. Distort travel
- **From home,** Distort for free to any place on your Distort list. You arrive at its **Waypost**.
- **From a place,** Distort home **only at that place's Waypost**. Blacking out also sends you home, under the normal blackout rules.
- **Between two places,** you go through home: Distort home from the first place's Waypost, then out to the second.
- **Session start** follows your real body, as always:
  - if the phone's latest fix lies inside a famous place, the session starts there — at the nearest revealed tile, per `design_travel_and_time.md` §4 — and that place unlocks;
  - otherwise it starts at home.
- **Distort costs no game time** and is never blocked by night.
- **Inside a place,** movement follows `design_travel_and_time.md`: the 15 mph clock, terrain, day and night.
- **In the story** (`design_story_and_world.md` §2.6), Walkers can step through the Distortion to firm ground they have walked. That's why you can't Distort somewhere you've never been.

---

## 5. Wardens (Decision 18 = B, refined by Decision 26)
- **When:** a region's Warden can be met only after **all three** of that region's cities are fully unlocked (§3.2).
- **Where:** each Warden waits at one fixed landmark. Their trials and Anchors are as in `design_story_and_world.md` §4.
- **Levels:** team level `22 + 6 × anchorsHeld`.
- **The finale needs all nine Anchors** — so the story requires physically visiting all 27 cities.

| Region | Warden | Landmark |
|---|---|---|
| New England | Maren Ashby (Ice) | Long Wharf, Boston |
| Middle Atlantic | Dex Ocampo (Steel) | Grand Central Terminal, New York |
| South Atlantic | Lucía Reyes (Grass) | Atlanta Botanical Garden, Atlanta |
| East South Central | Amos Whitlock (Fighting) | Tom Lee Park (riverfront), Memphis |
| West South Central | Rosa Tamez (Fire) | Zilker Park, Austin |
| East North Central | Ingrid Halvorsen (Water) | North Coast Harbor, Cleveland |
| West North Central | Calla Brandt (Flying) | Union Station, Kansas City |
| Mountain | Silas Vance (Ghost) | The Neon Boneyard, Las Vegas |
| Pacific | June Okafor (Psychic) | Griffith Observatory, Los Angeles |

---

## 6. Legendaries (Decision 26)
- **The lair.** Each legendary waits at a fixed lair inside its place, behind a **challenge** — a maze or puzzle you must clear in-game to reach it.
- **The same for everyone.** Lair layouts are generated from `(dex number, the global map seed)`, so every player meets the same challenge.
- **Starting challenge themes** (built in Phase 8):

  | Theme | Legendaries |
  |---|---|
  | Ice-slide floors | Articuno, Regice, Kyurem |
  | Lightning timing | Zapdos, Raikou, Thundurus |
  | Heat mirages | Moltres, Entei, Heatran |
  | Tide and current puzzles | Lugia, Kyogre, Manaphy, Phione, Suicune, Keldeo |
  | Rotating fog maze | Giratina, Darkrai |
  | Moon-phase gates | Cresselia |
  | Time-layer switches | Celebi, Dialga |
  | Warped-space doors | Palkia |
  | Rune doors (original symbols — never Nintendo's) | Regirock, Regice, Registeel |
  | Song sequence | Meloetta |
  | Assembly-line maze | Genesect |
  | Wind-current climb | Rayquaza, Tornadus |
  | A trail that moves | Mew, Latias, Latios |
  | Three-question trials | Uxie, Mesprit, Azelf |
  | Everything else | a hedge-and-boulder maze |

- **Requirements carried from the games' lore:**
  - Regigigas wakes only if Regirock, Regice, and Registeel are in your party;
  - Keldeo appears only once Cobalion, Terrakion, and Virizion are caught or defeated;
  - Arceus appears only once you hold all nine Anchors.
- **One decisive battle.** A legendary can be **caught or defeated once**; either ends it forever, and both count for the Pokédex. Blacking out or running away does **not** use up your chance — you redo the challenge and try again. *(This replaces the earlier 30-game-day respawn.)*

---

## 7. The same map for everyone (Decision 23 = A, and the human's rule "the map must be deterministic given the same location")
1. **A pinned snapshot.** Each game release names one OpenStreetMap snapshot date — **`MAP_SNAPSHOT = 2026-10-01`** — and downloads Geofabrik's dated file for it (`<region>-261001.osm.pbf` + `.md5`). Geofabrik keeps dated monthly extracts for years: checked 2026-10-20, 2024-01-01 was still served. The snapshot changes only in a new release, for everyone at once.
2. **Fixed conversion areas.** Each place is converted as one unit: its boundary's cell bounding box plus a 2-cell margin. That never depends on where the player has been.
3. **The whole coastline is always kept** for sea calculation, whatever else is clipped.
4. **One global map seed.** Every map-drawing choice — tree scatter, tall-grass patches, roof colours, empty lots, lair layouts — uses one constant seed, `MAP_SEED = 0`. Per-player seeds are used **only** for gameplay (encounters, hauntings).
5. **The result:** two players on the same game release see the identical map for the same place.

---

## 8. Getting map data onto the PC (Decision 23 = A)
- **Conversion happens on the player's PC,** one place at a time, in the background (the threaded install, `implementation_plan_world_generation.md` §5.4a).
- **What's downloaded** is the pinned file of the state (or California half) containing a place you can Distort to. It's kept on disk while other places in that state remain locked.
- **A download reveals only which state.** No request ever names a place, a cell, or a coordinate (Decision 13).

---

## 9. Configuration — `game/config/famous_places.json`
One entry per place — the 27 cities, the 36 legendary islands, and the 12 legendary spots inside cities:

| Field | Meaning |
|---|---|
| `id` | A stable slug, e.g. `"city:boston"`, `"site:acadia"`, `"spot:alcatraz"` |
| `kind` | `"city"`, `"site"`, or `"spot"` |
| `name` | The public name |
| `region` | One of the 9 Census divisions |
| `geofabrik` | The region path, e.g. `"north-america/us/massachusetts"` |
| `osm_boundary` | `"r<id>"` — the boundary relation (cities and sites) |
| `waypost` | `{name, lat, lon}` — city hall, or the site's main visitor centre or entrance (sites and cities) |
| `legendary_dex` | The legendary here (sites and spots) |
| `city` | The city id (spots only) |
| `warden` | `{name, type, landmark: {name, lat, lon}}` (one city per region) |

All coordinates are of **public landmarks**, never the human's. Ids and coordinates are filled in by agent guide Item 17 and reviewed by the human.
