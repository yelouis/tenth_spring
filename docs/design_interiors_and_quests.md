# Interiors & Side Quests — Famous Buildings You Can Enter, and the Quests That Tell What Happened

This is the contract for what players can walk *into*, and for the side quests that fill the world. It was requested by the human on 2026-10-20 (Decision 27, `ongoing_general_errors.md`). In their words: "Famous buildings or famous structures like the new york subway should be enterable. Anything [that] is enterable should serve a purpose… Make sure to have an abundant amount of side quests that help unlock what happened to the world/regions. These side quests should be like similar side quest/puzzles in the actual pokemon games."

**Content rules** (as in `design_story_and_world.md` §9):
- **Every layout, character, line of text, and puzzle here is original.** Puzzles follow the *kinds* of puzzles Pokémon games use (§3), never their maps, names, or text.
- **Real public buildings keep their real names.**
- **Never used as dungeons or battle sites:** memorials to tragedies, active places of worship, burial grounds, sites sacred to Native nations, and anything built around gambling.
- **Items, moves, and Pokémon are referenced by number;** their names come from the player's ROM.

---

## 1. What you can enter
1. **Famous interiors** — the famous buildings and structures listed in §4, inside the 27 cities and the 36 parks and wonders. Every one has a purpose (§2).
2. **Haunted interiors** — the root site of each haunted zone (`design_expeditions_and_survival.md` §2), always home to the zone boss.
3. **Legendary lairs** — when a legendary's place is a building or structure (Alcatraz, Independence Hall, Michigan Central Station, …), its challenge is that building's interior (`design_famous_places.md` §6).
4. **Ordinary buildings are not entered.** You **search them from the doorway**: one search action rolls the building's category item table (`design_resources_and_base.md` §1), with the same `untouched → partial → stripped` state.
   - **Why:** the human asked that anything enterable have a purpose. Thousands of identical empty houses would break that, while doorway searching keeps the scavenging survival loop.

**On the map,** a famous interior's building shows a **gold roof**, its name on a sign, and a **highlighted door**. Ordinary doors look ordinary.

---

## 2. Every interior has a purpose
Each famous interior carries **at least two** of these, and **at least one** must be a Trainer, Warden, Legendary, or a Quest step with a reward — nothing enterable is ever empty.

| Code | Purpose | What it means in play |
|---|---|---|
| **T** | Important trainer | A named survivor or specialist. Beating them gives a key item, a TM (by number), or a quest unlock. A rematch is available after the region's Warden. |
| **W** | Warden | A region's Warden trial (`design_famous_places.md` §5). |
| **L** | Legendary lair | The challenge and lair of the place's legendary — one decisive battle. |
| **H** | Hidden items | Items on the floor, some invisible until found with the **Dowsing Lantern** (§5.2). They regrow only through haunting (`design_expeditions_and_survival.md` §6). |
| **P** | Puzzle | One or more Pokémon-style puzzles (§3) gating the deeper rooms. |
| **Q** | Quest step | A step of a side quest or a regional "Truth" quest (§5) — a note, a person, a lock, a delivery. |
| **R** | Revival | A museum lab that revives fossils found in the field into fossil Pokémon (dex numbers by fossil). |
| **M** | Move tutor | Teaches a move (by number) after a task. |

**Interiors are the same for every player:**
- each is built from a **template family** (§4.1) and its puzzle modules, laid out by `(interior id, MAP_SEED)`;
- set pieces — a Warden's arena, a lair — are hand-authored data;
- a cleared interior stays cleared; its trainers stay beaten, its items taken.

---

## 3. Puzzle kinds — the Pokémon toolbox, made our own
These are the kinds of puzzles the Pokémon games use, described generically. Each interior picks from them.

| Kind | How it works | Typical home |
|---|---|---|
| **Switch hunt** | Find the hidden switches, in a set order, to open a gate. A wrong order resets them. | halls, theatres |
| **Warp tiles** | Floor pads teleport you inside the building; find the route to the goal. | towers, offices |
| **Spinner floor** | Arrows slide you until you hit an obstacle. | stations, factories |
| **Ice slide** | You slide until you hit something; plan the stops. | rinks, glaciers, ice caves |
| **Boulder push** | Push boulders onto pressure plates or into holes (needs a Strength-type key item). | caves, quarries, ruins |
| **Dark rooms** | Only a small circle around you is visible; the Lamp upgrades (Maren's Anchor perk) widen it. | tunnels, caves, the subway |
| **Invisible walls** | A maze of unseen walls; ghosts reveal them only through the **Veil Lens** (§5.2). | haunted interiors |
| **Elevator floors** | Find each floor's key card to unlock more floors. | skyscrapers |
| **Light and mirrors** | Rotate mirrors or lamps to send a beam to a target. | observatories, lighthouses |
| **Sequence** | Repeat a pattern — of notes, bells, signal flags, or lanterns. | music halls, belfries, signal towers |
| **Time of day** | A door opens only at dusk or at night, on the world clock. | anywhere "haunted" |
| **Footprint trail** | Follow tracks that appear only after a clue is found. | parks, gardens |
| **Counterweight** | Balance loads to move lifts, inclines, or drawbridges. | inclines, bridges, mills |

---

## 4. The famous interiors — starting list
*Starting content, like the spawn tables: the human may add, swap, or remove any row, and new rows follow §2.*
- **Purposes** use §2's codes.
- **Families:** `station`, `tower`, `museum`, `hall`, `arena`, `cave`, `lighthouse`, `industrial`, `prison`, `market`, `garden`, `underground`, `structure`.

### 4.1 Cities
| City | Interior | Family | Purposes | What's inside |
|---|---|---|---|---|
| **Boston** | Boston Public Library | hall | T Q P H | The Lantern Coast's archive. A librarian-trainer guards the stacks; a sliding-shelf puzzle hides Dr. Calder's New England log (§5.1). |
| Boston | Fenway Park | arena | T H | A double battle on the infield against two former ballplayers; hidden items in the stands. |
| Boston | Faneuil Hall (cupola) | hall | P Q | A weathervane-signal sequence puzzle in the cupola; a Lantern Coast Truth step. |
| **Providence** | Rhode Island State House | hall | Q T | Survivor Iris Calloway (Fire). A delivery quest begins here. |
| Providence | Providence Athenaeum | hall | P H | A hidden-library switch hunt; a TM at its heart. |
| **Portland (ME)** | Portland Observatory | lighthouse | P Q | A signal-flag sequence that calls the last ship. Part of the Lantern Coast Truth quest. |
| Portland (ME) | Old Port warehouses | industrial | T H | Ned Pruitt (Ice) and the cold storage he kept running. |
| **New York** | **The Subway** (Times Sq, Grand Central, Union Sq, and other stations) | underground | T Q P H | The Dead Grid's heart: dark tunnels; power switches that relight one line at a time; Priya Nandakumar (Ghost) on a platform; abandoned cars full of items; the Middle Atlantic Truth quest. |
| New York | Grand Central Terminal | station | W H | Warden Dex Ocampo's trial on the main concourse. |
| New York | Empire State Building | tower | P T | An elevator-floors climb to the observation deck, where a Flying specialist waits. |
| New York | Statue of Liberty | structure | L P | Jirachi's lair at the crown, up a spiral-stair sequence puzzle. |
| New York | American Museum of Natural History | museum | R Q H | The fossil-revival lab, and the Dome Fossil quest. |
| **Philadelphia** | Independence Hall | hall | L P | Victini's lair: a bell-and-door sequence. |
| Philadelphia | Philadelphia Museum of Art | museum | T P | The famous steps: a Fighting trainer at the top; a gallery mirror puzzle. |
| Philadelphia | Reading Terminal Market | market | Q H | The "Market Day" delivery quest; scavenging stalls. |
| **Pittsburgh** | Hot Metal Bridge | structure | L P | Registeel's lair inside the steel truss, behind rune doors. |
| Pittsburgh | Duquesne Incline | structure | P T | A counterweight puzzle to run the incline; Dorota Zielinski (Steel) at the top. |
| Pittsburgh | Cathedral of Learning | tower | Q P H | The university's research floors — and the first record of the Thinning (§5.1). |
| **Washington DC** | Library of Congress | hall | Q T P | The **Archive of the Stillness**, the hub of the world's mystery; survivor Marcus Bell (Psychic). |
| Washington DC | National Air and Space Museum | museum | Q H M | A move tutor; the "Lost Signal" quest. |
| Washington DC | Washington Monument | tower | P H | A wind-and-elevator climb; items at the top. |
| Washington DC | Lincoln Memorial | structure | L | Cobalion's lair, beneath the chamber. |
| **Atlanta** | Atlanta Botanical Garden (conservatory) | garden | W P | Warden Lucía Reyes; a vine-maze. |
| Atlanta | Fox Theatre | arena | T H | A performer-trainer; a backstage switch hunt. |
| Atlanta | Georgia Aquarium | museum | Q P | The "Last Keeper" quest: restore the tanks' pumps (valve puzzle) to free Water Pokémon. |
| **Miami** | Vizcaya Museum and Gardens | garden | P H | A hedge maze, with the bay's secrets in the grotto. |
| Miami | Freedom Tower | tower | Q T | Survivor Rafael Duarte (Water); the South Atlantic Truth quest. |
| **Nashville** | Ryman Auditorium | arena | L P | Meloetta's lair: a song-sequence puzzle. |
| Nashville | The Parthenon (Centennial Park) | hall | T P | A guardian-trainer, and a statue-and-shield light puzzle. |
| Nashville | Country Music Hall of Fame | museum | Q H | Lorraine Pike (Normal); recordings that piece together the Hollow Hills' last summer. |
| **Memphis** | The Pyramid | structure | P H | A spinner-floor climb to the summit. |
| Memphis | Sun Studio | hall | T Q | A recording quest; survivor Darnell Hayes (Water). |
| **Louisville** | Churchill Downs | arena | T Q | Hank Abernathy (Fire), and the "Last Race" timed challenge. |
| Louisville | Louisville Slugger Museum | museum | H Q | The giant bat hides a key item. |
| **New Orleans** | Preservation Hall | hall | T Q | Celestine Arceneaux (Ghost) and the Friday ghost parade — a night-only quest. |
| New Orleans | The Cabildo | museum | Q P H | Records of the Burnlands' flood year; an archive switch hunt. |
| New Orleans | French Market | market | H T | Stall scavenging; a cook-trainer. |
| **Houston** | Space Center Houston | museum | L P | Deoxys's lair: a launch-pad warp-tile maze. |
| Houston | Houston Astrodome | arena | T P H | The abandoned dome: a tournament ladder of 4 trainers; a dark-room maze below the field. |
| Houston | Houston Museum of Natural Science | museum | R Q | Fossil revival; Dr. Amir Haddad (Psychic). |
| **Austin** | Texas State Capitol | hall | Q P | A whispering-rotunda sequence; the West South Central Truth quest. |
| Austin | Congress Avenue Bridge (underside) | structure | Q H | A dusk-only bat-colony event (Zubat 41 swarm). |
| **Chicago** | Willis Tower | tower | P T | An elevator-floors climb to the glass ledge, where a Flying specialist waits. |
| Chicago | The "L" (elevated tracks) | structure | T P | Mae Kowal (Electric); track-switch routing. |
| Chicago | The Field Museum | museum | R Q H | Fossil revival; the Inland Seas Truth quest. |
| **Detroit** | Michigan Central Station | industrial | L P | Genesect's lair: an assembly-line spinner maze. |
| Detroit | Renaissance Center | tower | P T | A ring-corridor maze; Andre Moss (Steel). |
| Detroit | Fox Theatre (Detroit) | arena | H Q | Backstage items; a lost-reel quest. |
| **Cleveland** | Rock & Roll Hall of Fame | museum | T P Q | Rosie Dombrowski (Normal); a sound-sequence puzzle. |
| Cleveland | Terminal Tower | tower | Q H | Records of the frozen lake winter. |
| **Minneapolis** | Mill City Museum | industrial | P Q | A flour-mill gear puzzle in the ruins; the West North Central Truth quest. |
| Minneapolis | Stone Arch Bridge (piers) | structure | H T | Siri Lindqvist (Ice). |
| **St. Louis** | Gateway Arch | structure | L P | Arceus's lair, up the tram — it opens only with all nine Anchors. |
| St. Louis | City Museum | museum | P H T | A maze of tunnels and slides, built for puzzles; Calvin Brooks (Water). |
| St. Louis | Missouri Botanical Garden | garden | Q H | A footprint-trail quest. |
| **Kansas City** | Union Station | station | W H | Warden Calla Brandt. |
| Kansas City | Nelson-Atkins Museum of Art | museum | P Q | A giant-sculpture garden puzzle; Rita Delgado (Fire). |
| **Las Vegas** | The STRAT tower | tower | P T | A wind-gust climb to the top; Lucky Morales (Psychic). |
| Las Vegas | Fremont Street arcade | market | H Q | The Neon quest — relight the old signs (light-routing puzzle). |
| **Denver** | Colorado State Capitol | hall | Q P | The "Mile High" sequence; the Mountain Truth quest. |
| Denver | Denver Museum of Nature & Science | museum | R H | Fossil revival; Hana Mori (Rock). |
| **Phoenix** | Desert Botanical Garden | garden | P H | A cactus-maze footprint trail. |
| Phoenix | Arizona Capitol Museum | hall | Q T | Elena Ruiz (Water) and the last canal-water records. |
| **San Francisco** | Alcatraz Island (cellhouse) | prison | L P | Mewtwo's lair: a cellblock switch-and-door maze. |
| San Francisco | Cable Car Museum | industrial | T P | Kenji Watanabe (Electric); a cable-wheel counterweight puzzle. |
| San Francisco | Coit Tower | tower | P Q | A mural-panel sequence; the Pacific Truth quest. |
| **Los Angeles** | Griffith Observatory | hall | W P | Warden June Okafor; a mirrors-and-light puzzle in the planetarium. |
| Los Angeles | TCL Chinese Theatre | arena | T Q | Valentina Cruz (Fighting); a stunt-course challenge. |
| **Seattle** | **Seattle Underground** | underground | P Q H | The buried old streets: invisible walls, and the **Veil Lens** at the bottom (§5.2). |
| Seattle | Space Needle | tower | P T | An elevator climb; Nora Kittredge (Water). |
| Seattle | Pike Place Market | market | H Q | Scavenging; the "Fishmonger's Debt" delivery quest. |

### 4.2 Parks and wonders
Every park and wonder has its **visitor centre** — family `hall`, purposes **T Q H**: a ranger-trainer, the park's lore quest, and supplies. Where the legendary's place is a cave or a building, that interior **is** the lair (**L P**):

| Place | Lair interior |
|---|---|
| Mammoth Cave | cave — Terrakion, behind boulder pushes |
| Carlsbad Caverns | cave — Giratina, in a rotating fog maze |
| Russell Cave | cave — Regirock, behind rune doors |
| Thomas Edison NHP | the laboratory — Zekrom, behind generator switches |
| Salem Maritime NHP | the Custom House — Darkrai, in a dark rooms nightmare maze |
| Cape Hatteras | the lighthouse — Lugia, behind a light-and-mirrors puzzle |
| Wright Brothers Memorial | the hangar and dunes — Rayquaza, up a wind-current climb |
| Niagara Falls | the Cave of the Winds — Azelf, behind three-question trials |

Elsewhere the lair is an outdoor maze inside the park.

**Counts:** **71** city interiors and **36** visitor centres, plus the lairs. That's at least 107 enterable places, each with a purpose.

---

## 5. Side quests — abundant, Pokémon-style, and each telling part of what happened

### 5.1 The world's mystery — "The Calder Logs"
**Dr. Ruth Calder** was a geographer who, years before the Stillness, mapped the places people had stopped visiting, and noticed they were getting *thin*. When the fog came she travelled the country recording it, and left **nine field logs, one per region**, before she vanished.
- Each region's **Truth quest** ends with one log.
- In any order, the logs explain the world's rules: why the fog feeds on absence, why Walkers hold it back, why legendaries and Anchors can't be copied. The ninth explains what the Distortion is becoming — **the Echo** — and why it chose you.
- With all nine logs read, the Archive of the Stillness (Library of Congress) shows her last entry. It's optional lore before the finale. The Echo finale itself (`design_story_and_world.md` §5) never requires the logs.
- **Each log's text is original prose, and lives in game data.**

### 5.2 Key-item quests — the tools that open the world
| Quest | Where | Reward (key item) | It opens |
|---|---|---|---|
| **The Ranger's Lantern** | any park's visitor centre (first one visited) | **Dowsing Lantern** — reveals invisible hidden items | every **H** with hidden items |
| **Below the Streets** | Seattle Underground | **Veil Lens** — lets you see ghosts and their invisible walls | **invisible-wall** puzzles; hidden Ghost trainers in haunted interiors |
| **The Strongman's Promise** | Philadelphia Museum of Art | **Lift Gloves** (Strength-type field use) | **boulder-push** puzzles |
| **Power to the Line** | the New York Subway | **Line Key** — restarts dead elevators and lifts | **elevator-floors** puzzles |
| **The Bicycle** | any `shop=bicycle` or hardware site (`design_resources_and_base.md` §4) | **Bicycle** | ×2 travel speed inside places |
| **The Ferryman's Oar** | Cleveland — after Ingrid's trial | **River Oar** (crossing small water) | water-crossing routes inside places |

### 5.3 Regional Truth quests — one per region, 4–6 steps
Each starts at the region's first-visited city and threads through all three cities and at least one park. It ends with that region's Calder log, which reveals how the region went dark (story §4a):

| Region | Truth quest | Spine |
|---|---|---|
| New England | **The Last Light** | Relight three harbour lamps in order (Boston, Providence, Portland) and learn why the lighthouses failed first. |
| Middle Atlantic | **The Night the Grid Failed** | Restore subway power line by line; recover the transit control log; climb the Cathedral of Learning for the Thinning's first data. |
| South Atlantic | **The Long Summer** | Track the vine-growth records from the Archive to Atlanta's garden and Miami's tower. |
| East South Central | **Hollow Voices** | Collect field recordings in Nashville, Memphis, and Louisville that capture the mines "breathing" fog. |
| West South Central | **Smoke and Water** | Follow the wildfire crews' maps and the flood records in the Cabildo; a ghost-parade night in New Orleans. |
| East North Central | **The Frozen Winter** | Reconstruct the ice winter from the Field Museum, the Renaissance Center, and Terminal Tower. |
| West North Central | **Storm Cellars** | Find the storm logs in the Mill City ruins, the City Museum's tunnels, and the Nelson-Atkins garden. |
| Mountain | **The Towns That Went First** | Ghost-town ledgers from Las Vegas, Denver, and Phoenix; the reason Ghosts are calm here. |
| Pacific | **What the Fog Copies** | June Okafor's own observations: Coit Tower murals, Griffith's mirrors, and the Seattle Underground. |

### 5.4 Side-quest kinds — the Pokémon patterns, made our own
| Kind | Pattern | Example |
|---|---|---|
| **Fossil revival** | Find a fossil in the field; revive it at a museum lab (**R**). | Dome Fossil → Kabuto (140) at the American Museum of Natural History |
| **Show me** | An NPC asks to *see* a Pokémon with a trait (type, move, size, time of day). The reward is an item or a move. | "Show me a Fire-type at night" — Rita Delgado, Kansas City |
| **Delivery chain** | Carry letters or parcels between survivors in different cities. Needs Distort, so it rewards real travel. | "Letters Home": 6 letters across 4 regions |
| **Collectible set** | Find all of a scattered set; each piece tells part of a story. | **The Lost Postcards**: 81 postcards, 3 hidden per city, each a pre-Stillness message; complete sets reward Poké Balls and a TM per region |
| **Rematch circuit** | Beat a region's three survivors again at a higher level after its Warden. | "Old Friends", per region |
| **Lost item** | Return a lost belonging. | A stage magician's lost cane (Las Vegas) |
| **Night-only event** | Something happens only at dusk or night on the world clock. | The bat colony (Austin); the ghost parade (New Orleans) |
| **Real-world gated** | Unlocked by real movement — **access only, never cargo** (pillar 2). | "Night Walker": be in a famous city in real life after dark (by the phone fix's time) to meet a hidden Ghost trainer there |
| **Move tutor** | Do a task; learn a move. | Air and Space Museum |
| **Legendary hint** | A short quest before each legendary's challenge — find runes, notes, or tracks. | Three rune tablets before the Regi doors |

### 5.5 How many — the abundance targets
| Kind | Target |
|---|---|
| Regional Truth quests | **9** — one per region |
| Key-item quests | **6** (§5.2) |
| City side quests | **≥ 4 per city → ≥ 108** |
| Park side quests | **≥ 1 per park or wonder → ≥ 36** |
| Legendary hint quests | **48** — one per legendary |
| Cross-country chains | **≥ 4**: Lost Postcards, Letters Home, Old Friends, Night Walker |

**Total: about 210 or more**, all written as data (§6).

---

## 6. Data and files (built in Phases 7–8)
- **`game/data/interiors/<interior id>.json`** — family, floors, the puzzle modules and their parameters, NPC ids, item spots (item numbers), the lair or Warden set piece, and the place id and door position. Layouts come from `(id, MAP_SEED)` plus authored set pieces.
- **`game/data/quests/<quest id>.json`** — steps (trigger → condition → effect), rewards (item numbers, move numbers, access flags), lore text (original), and region.
- **`game/data/lore/`** — the Calder logs, the Lost Postcards, and NPC dialogue. All original prose.
- **Engine:** `game/explore/interior_generator.gd`, `game/explore/puzzles/*.gd` (one per §3 kind), `game/quests/quest_engine.gd`, `game/ui/journal.gd` (the Walker's Journal: quests, logs, postcards).
- **Save** (a later migration): `quest_progress(quest_id, step, state)`, `interior_state(interior_id, cleared, items_json)`, `lore_found(lore_id)`.
- **Golden invariant 1 still holds:** quests and interiors are play state. The sync ingest never writes them. A real-world-gated quest only *unlocks* a step; the reward is still earned in play.
