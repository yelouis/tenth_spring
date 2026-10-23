# Interiors & Side Quests — Famous Buildings You Can Enter, and the Quests That Tell What Happened

This is the contract for what players can walk *into*, and for the side quests that fill the world. It was requested by the human on 2026-10-20 (Decision 27, `ongoing_general_errors.md`). In their words: "Famous buildings or famous structures like the new york subway should be enterable. Anything [that] is enterable should serve a purpose… Make sure to have an abundant amount of side quests that help unlock what happened to the world/regions. These side quests should be like similar side quest/puzzles in the actual pokemon games."

**Content rules** (as in `design_story_and_world.md` §9):
- **Every layout, character, line of text, and puzzle here is original.** Puzzles follow the *kinds* of puzzles Pokémon games use (§3), never their maps, names, or text.
- **Real public buildings keep their real names.**
- **Never used as dungeons or battle sites:** memorials to tragedies, active places of worship, burial grounds, and sites sacred to Native nations.
- **Casinos may appear** (Decision 33, 2026-10-22) — Las Vegas's Glow is a working society. **But the game never simulates betting or games of chance:** the Glow's games are skill and logic games (§3), and Glow chips are earned by winning them or by battling.
- **Items, moves, and Pokémon are referenced by number;** their names come from the player's ROM.

---

## 1. What you can enter
1. **Famous interiors** — the famous buildings and structures listed in §4, inside the 27 cities and the 60 parks and wonders. Every one has a purpose (§2).
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

**Every puzzle has an in-world reason** (pass-19 content review, 2026-10-21). Someone built it, or the collapse made it. A puzzle that exists only to be a puzzle breaks the world, so each interior's data names its reason, and its text says it in the world's voice.

| Kind | How it works | Why it's there | Typical home |
|---|---|---|---|
| **Switch hunt** | Find the hidden switches, in a set order, to open a gate. A wrong order resets them. | Survivors barricaded the deeper rooms and hid the releases. | halls, theatres |
| **Warp tiles** | Floor pads teleport you inside the building; find the route to the goal. | Thin spots: the fog folds a building's rooms into each other. | towers, offices |
| **Spinner floor** | Arrows slide you until you hit an obstacle. | Old conveyors and moving walkways still run on stray power. | stations, factories |
| **Ice slide** | You slide until you hit something; plan the stops. | Burst pipes froze, and the cold never left. | rinks, glaciers, ice caves |
| **Boulder push** | Push boulders onto pressure plates or into holes (needs the Lift Gloves). | Rockfalls and rubble from the collapse. | caves, quarries, ruins |
| **Dark rooms** | Only a small circle around you is visible; the Lamp upgrades (Maren's Anchor perk) widen it. | The power is out, and the fog swallows light. | tunnels, caves, the subway |
| **Invisible walls** | A maze of unseen walls; ghosts reveal them only through the **Veil Lens** (§5.2). | Rooms the fog has half-copied: the walls are real, but only ghosts can see them. | haunted interiors |
| **Elevator floors** | Find each floor's key card to unlock more floors. | The building's security still locks its floors. | skyscrapers |
| **Light and mirrors** | Rotate mirrors or lamps to send a beam to a target. | Survivors signal with light — and the fog fears a kept light. | observatories, lighthouses |
| **Sequence** | Repeat a pattern — of notes, bells, signal flags, or lanterns. | A survivor's code, or an old custom of the place. | music halls, belfries, signal towers |
| **Time of day** | A door opens only at dusk, at night, or under one phase of the moon (phase = game day mod 8). | The fog thins and thickens with the hour. | anywhere "haunted" |
| **Footprint trail** | Follow tracks that appear only after a clue is found. | Someone — or something — walked here before you. | parks, gardens |
| **Counterweight** | Balance loads to move lifts, inclines, or drawbridges. | Old machinery that works by weight alone, with no power at all. | inclines, bridges, mills |
| **Rune doors** | Doors marked with original symbols open in the order shown on rune tablets found nearby. | The legendary giants sealed themselves in. | Regi lairs |
| **Quiz** | A voice asks three questions, answered from your own Walker's Journal. | Some things test what you've truly seen. | lake-trio lairs, archives |
| **Currents and tides** | Water pushes you along channels, and some ground floods and drains with the hour. | Real water, moving as it always has. | coasts, rivers, falls |
| **Gusts** | Wind tiles push you a set distance; time your steps between gusts. | Storms the fog drags across open ground. | dunes, rooftops, prairie |
| **Hazard timing** | Lightning, steam vents, or lava hit tiles in a cycle; cross between them. | Nature, unwatched for ten years. | storm country, springs, volcanoes |
| **Mirage** | False paths look walkable; only real ground casts a shadow at noon. | Heat — and the fog copying the ground it lies on. | deserts |
| **Time layers** | A switch flips the area between two eras, each with different walls and bridges. | Time slips where the fog crowds around something old. | ancient places |
| **Mirror room** | A copy of you moves opposite you; use it to press switches you can't reach. | The fog copying you — the Echo, learning. | Pacific interiors, late game |
| **Fuse board** *(pass 20)* | A grid of hidden panels. Each row and column shows how much power it holds and how many shorts. Flip panels to collect power and avoid the shorts; a short resets the board. | The House's skill game — how the Glow hires its electricians. | the Glow; Diancie's "gem board" variant |
| **Card wall** *(pass 20)* | Flip cards two at a time to find pairs before the lights cycle. | Another of the Glow's skill games. | the Glow |
| **Sliding tiles** *(pass 20)* | Slide panels to rebuild a picture or a map. | Murals and maps shattered in the collapse, which survivors piece back together. | museums, ruins, Regi doors |
| **Pipe routing** *(pass 20)* | Rotate pipe or wire pieces to connect a source to every outlet. | Survivors' patched-together lines. | plants, aquariums, springs |
| **Weight plates** *(pass 20)* | Set Pokémon from your party on scales; the right total weight opens the gate. | Old freight scales that still work the doors. | stations, mills, docks |
| **Cipher wheel** *(pass 20)* | Decode Calder's field notes with the cipher wheel from her first log; the decoded word opens a lock. | Calder wrote in a field cipher in case her notes were found by the wrong people. | archives, Truth quests |
| **Lantern relay** *(pass 20)* | Carry a flame from lantern to lantern before it burns out. | The keepers' way of passing light down the coast. | the Lantern Coast |
| **Echo pings** *(pass 20)* | In darkness, a limited number of calls light up the nearby walls for a moment. | How bats, and miners, find their way. | caves, mines, deep vaults |
| **Shadow pinning** *(pass 20)* | Your shadow moves on its own; lead it under lamps to pin it while you pass. | Something in the shade learns by watching you. | bayous, theatres |
| **Ring portals** *(pass 20)* | Rings link in pairs — step into one, out of its pair. Some rings move on a timer. | A trickster's mischief. | Coney Island |
| **Cell hunt** *(pass 20)* | Find scattered cells — some only at night, some only in rain — across a place, or across the country. | A guardian whose body is spread through the land it protects. | Zygarde's 100 cells |
| **Growth paths** *(pass 20)* | Plant a seed from your home garden at a marked spot, and it grows a vine bridge or a stepping trunk. | Life answers life. | Xerneas's grove, gardens |
| **Race** *(pass 20)* | Reach the goal before a hazard front — a storm, a shadow — catches you. | Things here move faster than anything should. | salt flats, racetracks |

### 3.1 Each region's signature puzzle
Each region leans on one kind that comes from how it went dark (`design_story_and_world.md` §4a). Its interiors use that kind at least once.

| Region | Signature | Why |
|---|---|---|
| New England | **Light and mirrors** — lamps to relight and beams to aim | the Lantern Coast kept its lights |
| Middle Atlantic | **Switch hunts that restore power**, one line at a time | the Dead Grid |
| South Atlantic | **Water and vines:** valves feed water to the roots, and watered vines pull back | the Green Tide |
| East South Central | **Echo sequences** — repeat what the hollow plays back | the hills breathe and echo |
| West South Central | **Hazard timing** — vents, mirages, firebreaks | the Burnlands |
| East North Central | **Ice slides and counterweights** — frozen floors, harbour cranes | the ice winter |
| West North Central | **Gusts**, and dark storm cellars | the Open Sky |
| Mountain | **Invisible walls** shown by calm ghosts, if you come at the right hour | the Ghost Frontier |
| Pacific | **Mirror rooms** | the Edge, where the fog learned to copy |

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
| Boston | Arnold Arboretum | garden | L P | Enamorus's lair: walk the trees in the order spring wakes them (§4.3). |
| **Providence** | Rhode Island State House | hall | Q T | Survivor Iris Calloway (Fire). A delivery quest begins here. |
| Providence | Providence Athenaeum | hall | P H | A hidden-library switch hunt; a TM at its heart. |
| **Portland (ME)** | Portland Observatory | lighthouse | P Q | A signal-flag sequence that calls the last ship. Part of the Lantern Coast Truth quest. |
| Portland (ME) | Old Port warehouses | industrial | T H | Ned Pruitt (Ice) and the cold storage he kept running. |
| **New York** | **The Subway** (Times Sq, Grand Central, Union Sq, and other stations) | underground | T Q P H | The Dead Grid's heart: dark tunnels; power switches that relight one line at a time; Priya Nandakumar (Ghost) on a platform; abandoned cars full of items; the Middle Atlantic Truth quest. |
| New York | Grand Central Terminal | station | W H | Warden Dex Ocampo's trial on the main concourse. |
| New York | Empire State Building | tower | P T | An elevator-floors climb to the observation deck, where a Flying specialist waits. |
| New York | Statue of Liberty | structure | L P | Jirachi's lair at the crown, up a spiral-stair sequence puzzle. |
| New York | American Museum of Natural History | museum | R Q H | The fossil-revival lab, and the Dome Fossil quest. |
| New York | Coney Island | structure | L P | Hoopa's lair: ring portals across the boardwalk and the rides. |
| **Philadelphia** | Independence Hall | hall | L P | Victini's lair: a bell-and-door sequence. |
| Philadelphia | Philadelphia Museum of Art | museum | T P | The famous steps: a Fighting trainer at the top; a gallery mirror puzzle. |
| Philadelphia | Reading Terminal Market | market | Q H | The "Market Day" delivery quest; scavenging stalls. |
| Philadelphia | The Franklin Institute | museum | L P Q | Magearna's lair: a clockwork maze that runs only with the four heart gears; the gear hunt starts here. |
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
| **Louisville** | Churchill Downs | arena | T Q L P | Hank Abernathy (Fire), the "Last Race" timed challenge, and Spectrier's night race (§4.3). |
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
| Cleveland | The Flats | industrial | L P | Meltan's lair: magnet cranes and scrap — rebuild a path through the rusting mills. |
| **Minneapolis** | Mill City Museum | industrial | P Q | A flour-mill gear puzzle in the ruins; the West North Central Truth quest. |
| Minneapolis | Stone Arch Bridge (piers) | structure | H T | Siri Lindqvist (Ice). |
| **St. Louis** | Gateway Arch | structure | L P | Arceus's lair, up the tram — it opens only with all nine Anchors. |
| St. Louis | City Museum | museum | P H T | A maze of tunnels and slides, built for puzzles; Calvin Brooks (Water). |
| St. Louis | Missouri Botanical Garden | garden | Q H | A footprint-trail quest. |
| **Kansas City** | Union Station | station | W H | Warden Calla Brandt. |
| Kansas City | Nelson-Atkins Museum of Art | museum | P Q | A giant-sculpture garden puzzle; Rita Delgado (Fire). |
| **Las Vegas** | **Fremont Street — the Glow** | market | T Q H | The casino town that never went dark (`design_story_and_world.md` §4b): the Glow Arena, the House's skill games (fuse board, card wall), trade in Glow chips, and the House's rules. |
| Las Vegas | The STRAT tower | tower | P T | The Glow's beacon: a wind-gust climb to the top, where the House's champion waits. |
| Las Vegas | The House vault (beneath Fremont Street) | underground | L P | Necrozma, kept in the dark — the secret of the Glow's lights. Mirrors route the stolen light; turn them back toward the desert towns. |
| Las Vegas | The Neon Museum (the Boneyard) | museum | W Q P | Warden Silas Vance among the signs of the towns that went dark; relight them (light routing). |
| Las Vegas | The Smith Center | arena | T P | Lucky Morales (Psychic) and his backstage vanishing-cabinet maze (warp tiles). |
| Las Vegas | Springs Preserve | garden | Q H | The springs where the city began; a Mountain Truth step — why the desert cities lost their water. |
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
| Mammoth Cave | cave — Terrakion, boulder pushes in dark passages |
| Carlsbad Caverns | cave — Giratina, the reverse room |
| Cathedral Caverns | cave — Regirock, rune doors and boulders beneath Goliath |
| Craters of the Moon | lava tubes — Cresselia, moon-phase gates |
| Hawaiʻi Volcanoes | an old lava tube — Heatran, lava pulses (never the summit crater) |
| Mount Washington | the summit weather station — Regice, rune doors on ice |
| Thomas Edison NHP | the laboratory — Zekrom, dynamo switches |
| Cape Hatteras | the lighthouse — Lugia, light and mirrors |
| Wright Brothers Memorial | the dunes and the monument — Rayquaza, gusts |
| Niagara Falls | the Cave of the Winds — Mesprit, voices in the mist |
| Ruby Falls | cave — Regieleki, rune doors and live wiring (pipe routing) |
| Red River Gorge | the sealed chamber behind an arch — Regidrago, rune doors and a sliding-tile dragon's head |
| McDonald Observatory | the great telescope's dome — Cosmog, light and mirrors |
| Kennedy Space Center | the launch gantry — Solgaleo, a noon-only climb |
| Minuteman Missile | the silo — Type: Null, elevator floors and a two-key switch |
| Boston Harbor Islands | Boston Light — Tapu Fini, a lantern relay through the mist |
| Dry Tortugas | Fort Jefferson — Tapu Koko, lightning timing on the parapets |
| Meteor Crater | a cavern under the crater floor — Eternatus, echo pings in the dark |

Elsewhere the lair is outdoors, inside the park (§4.3).

**Counts:** **79** city interiors and **60** visitor centres, plus the lairs. That's at least 139 enterable places, each with a purpose.

*Changed 2026-10-22 (Decision 33):* Las Vegas's casinos are back, as the Glow. *(Pass 19 had removed the STRAT tower and Fremont Street under a no-gambling rule that the human has since lifted.)* The Glow never simulates betting.

### 4.3 Legendary lairs — one challenge each
Each legendary's challenge comes from what it is: the Distortion can't copy a legendary, so it crowds around one, and the ground warps into the legendary's own shape (`design_famous_places.md` §6). The lore requirements are in that section. Layouts come from `(dex, MAP_SEED)`, and the set pieces are authored.

| Legendary | Place | Challenge | Why it's there |
|---|---|---|---|
| Articuno | Acadia | **Ice slide** across the frozen tide pools below the cliffs | its cold freezes the sea spray, and the fog keeps it frozen |
| Regice | Mount Washington | **Rune doors on ice** in the summit weather station | the rime ice is its breath |
| Uxie | Walden Pond | **Quiz** at the cabin site — a Warden's name, a log's rule, a place you explored | it can only ask about what you've truly seen |
| Phione | Cape Cod | **Tides** — cross the flats to its drifting pool at low tide | it drifts with the real tide |
| Darkrai | Katahdin Woods and Waters | **Starlight maze** — a pitch-dark forest; each star marker you find lights one more star and one more step of trail | its nightmares feed on the darkest sky in the East, but starlight is one light it can't swallow |
| Registeel | Hot Metal Bridge | **Rune doors over spinner plates** inside the truss | the old rolling-mill rollers still turn |
| Jirachi | Statue of Liberty | **Sequence** — light the crown's 25 windows in the order on the survivors' wish notes at the pedestal | it wakes for wishes, and the survivors kept leaving them |
| Mesprit | Niagara Falls | **Voices in the mist** behind the falls: you see nothing past the spray, and each survivor you've helped adds a voice that calls one more turn | it answers feeling; the people you helped guide you |
| Victini | Independence Hall | **Bell and door sequence**, its rhythm on a survivor's victory banner | survivors rang the bells for every battle won |
| Zekrom | Thomas Edison NHP | **Dynamo switches** — route power through the old generators, in the order in the lab's notebooks | its charge still hums in the dynamos |
| Zapdos | Everglades | **Hazard timing** — cross the sawgrass boardwalks between lightning strikes; each flash shows the next | it rides the summer storms |
| Mew | Great Smoky Mountains | **A trail that moves** — its tracks fade and reappear in the mist, changing every game hour | it plays |
| Lugia | Cape Hatteras | **Light and mirrors** — relight the lens and send its beam out to sea | the lighthouse that warned ships off this coast now calls the guardian of the deep |
| Rayquaza | Wright Brothers Memorial | **Gusts** up Big Kill Devil Hill | the hill where flight began |
| Manaphy | Biscayne | **Currents** between the keys, to a sea grotto | the open sea |
| Cobalion | Lincoln Memorial | **Fair fights** in the undercroft: three trainers, each battle limited to the number of Pokémon your opponent carries | it tests whether you fight fairly |
| Raikou | Waterfront Park, Louisville | **Hazard timing** — the old fireworks barges crackle in a cycle | "Thunder" never quite went out |
| Regirock | Cathedral Caverns | **Rune doors and boulder pushes** beneath Goliath | the giants sealed themselves in |
| Groudon | Reelfoot Lake | **Shifting ground** — push boulders onto plates before each aftershock slides them away | the land here still remembers the earthquakes |
| Terrakion | Mammoth Cave | **Boulder pushes in dark rooms** | rockfalls, and its charges |
| Meloetta | Ryman Auditorium | **Song sequence** — repeat the melody the empty stage plays back, verse by verse | Music City's last song |
| Moltres | Big Bend | **Mirage** | its heat |
| Entei | Hot Springs | **Steam vents** along the old bathhouse pipes (hazard timing) | water heated deep in the earth |
| Kyogre | Padre Island | **Tides** — reach the sandbar at low tide | the open Gulf |
| Deoxys | Space Center Houston | **Warp pads** to three rooms — attack, defence, speed — clear all three | it shifts its form, and the rooms shift with it |
| Virizion | Buffalo National River | **Footprint trail** of hoofprints that shows only at dawn | it moves through the Ozark forests at first light |
| Suicune | Cuyahoga Valley | **Switch hunt** — open three channels to flush the polluted pools clean | it comes only to clean water |
| Azelf | Isle Royale | **Endurance** — cross the island with no items, through five wild battles in a row | it tests willpower, as the island's wolves and moose were tested |
| Regigigas | Sleeping Bear Dunes | **Sand slide** — the steep dune faces slide like ice | the dunes are its bed |
| Tornadus | Northerly Island | **Gusts** off the lake, along the shore paths | the Windy City |
| Genesect | Michigan Central Station | **Spinner floors** — an assembly line through the station halls | the Motor City's machines, still running |
| Latias | Bde Maka Ska | **A trail that moves** across the frozen lake, marked by ripples that shift every game hour | it hides by bending light |
| Latios | Voyageurs | **A trail that moves** between islands, on the water's reflection | the other of the pair waits where the lakes run north |
| Arceus | Gateway Arch | **The nine plates** — the tram runs only with all nine Anchors; at the top, set each on its plate in the order you earned them | the Alpha answers only to someone who has held the whole country |
| Thundurus | Badlands | **Hazard timing** across the badlands ridges | prairie thunderstorms |
| Landorus | Tallgrass Prairie | **Footprint trail** — bison paths through head-high grass | land and harvest |
| Ho-Oh | Yellowstone | **Sequence** — step on the hot-spring rims in rainbow order | Grand Prismatic's colours |
| Dialga | Grand Canyon | **Time layers** — switches flip the canyon between two eras, and a bridge exists in only one of them | two billion years in the rock |
| Palkia | Arches | **Warp tiles** — each arch is a door to another | gaps opened in space |
| Giratina | Carlsbad Caverns | **The reverse room** — the Big Room flips, and you climb what was the ceiling | a hidden world below |
| Cresselia | Craters of the Moon | **Moon-phase gates** in the lava tubes (time of day). Gives the **Moon Feather** once caught or defeated | a moonscape |
| Reshiram | White Sands | **Light and mirrors** on the dunes — aim the noon glare at a stone of truth | white dunes |
| Mewtwo | Alcatraz | **Cellblock switches** — each lever opens one door and closes another | a cell built to hold anything |
| Celebi | Redwood | **Time layers** — touch the ancient stumps to step back into the old forest, where the path is different | ancient forest — time |
| Heatran | Hawaiʻi Volcanoes | **Lava pulses** in an old lava tube; step on the cooled crust between them (hazard timing). Never the summit crater | living lava |
| Shaymin | Mount Rainier | **Blooming trail** — meadow flowers open along the right path as you walk it | wildflower meadows |
| Kyurem | Glacier Bay | **Ice slide** across the glacier, around the crevasses | ice |
| Keldeo | Yosemite | **Currents and spray** — stepping stones below the falls, hidden by spray until you're beside them | waterfalls |
| **Generations 6–8** *(Decision 32)* | | | |
| Tapu Fini | Boston Harbor Islands | **Lantern relay** through the island mist to Boston Light | it guards the oldest light on the coast |
| Kubfu | Monadnock | **Endurance** — climb past five trainers in a row with no items. Then choose its trial: the **Shadow** (dark rooms) or the **Tide** (currents), which decides its form when it evolves | it trains every day |
| Calyrex | Marsh-Billings-Rockefeller | **Sequence** — tend the old fields in the order of the season's work, carrying a harvest from your garden | the harvest king remembers tending |
| Enamorus | Arnold Arboretum | **Sequence** — walk the trees in the order spring wakes them, as each comes into bloom | she brings the spring |
| Hoopa | Coney Island | **Ring portals** across the boardwalk and the rides; the rings move each hour | its mischief |
| Lunala | Cherry Springs | **Sequence** — trace tonight's constellations on the field's star markers (they change with the game day) | it comes to watch the sky |
| Magearna | Franklin Institute | **A clockwork maze** that turns only with the four heart gears in place (counterweight) | its soul is a gear |
| Glastrier | Adirondacks | **Ice slide** down the old bobsled run | the ice track never thaws |
| Tapu Koko | Dry Tortugas | **Hazard timing** — lightning walks the fort's parapets in a cycle; the moat's currents carry you between bastions | it keeps watch over the Gulf's storms |
| Solgaleo | Kennedy Space Center | **Elevator floors** up the launch gantry; the top opens only at noon (time of day) | it waits for the sun |
| Zarude | Congaree | **Growth paths and currents** — swing between vine anchors over the flooded forest floor | its troop's jungle |
| Tapu Lele | Gulf Islands | **Currents and tides** between the islands; its scales mark safe water | it heals the storm-washed |
| Regieleki | Ruby Falls | **Rune doors and pipe routing** — live wiring powers each door | the giant makes the current |
| Regidrago | Red River Gorge | **Rune doors and sliding tiles** — rebuild the carved dragon's head | the giant sleeps behind the arch |
| Spectrier | Churchill Downs | **Race** — the shadow horse's lap of the track at midnight; finish before it does (time of day) | the fastest thing on the course |
| Zygarde | Barataria Preserve | **Cell hunt** — 50 of its 100 cells, across the country; at the lair, the cells light a path through the marsh maze | its body is spread through the land |
| Diancie | Crater of Diamonds | **Fuse board** (the gem variant) — dig the field's squares by the clues; a wrong dig collapses the trench | something under the field makes jewels |
| Cosmog | McDonald Observatory | **Light and mirrors** — turn the great telescope's mirrors until the starlight lands where it sleeps | the nebula on the mirror |
| Marshadow | Caddo Lake | **Shadow pinning** among the cypress and moss | it learns by watching |
| Tapu Bulu | Apostle Islands | **Water and vines** in the sea caves — vines close behind you unless their roots are watered | its forest takes back the untended |
| Meltan | the Flats | **Counterweight** — magnet cranes lift scrap to rebuild a path through the mills | it eats metal |
| Zacian | Porcupine Mountains | **Footprint trail** — follow the wolf's tracks through deep snow to the Lake of the Clouds overlook | the north woods' guide |
| Zamazenta | Pictured Rocks | **Boulder push** in the cliff caves, against the rising lake (tides) | the cliffs are its shield |
| Yveltal | Theodore Roosevelt | **Hazard timing** — a dark wing passes over the buttes in a cycle, draining HP from your party; move from shadow to shadow | it drains life |
| Type: Null | Minuteman Missile | **Elevator floors** down the silo, then a **two-key switch**: two levers that must turn within three steps of each other | it was built for a war that never came |
| Necrozma | the vault beneath Fremont Street | **Light and mirrors** — turn the House's mirrors to send the stolen light back to the desert towns; each town relit opens a door | the Glow's secret |
| Zeraora | Bonneville | **Race** across the salt ahead of the storm front | it outruns lightning |
| Eternatus | Meteor Crater | **Echo pings** in the cavern under the crater floor, where it waits **fog-swollen** (`design_long_game.md` §4.4) | a darkness the fog won't go near |
| Xerneas | Sequoia | **Growth paths** — plant seeds from your home garden to grow bridges between the giants | life answers life |
| Volcanion | Lassen | **Steam vents and pipe routing** — redirect the boiling water to cool a path | it guards the wild with steam |

---

## 5. Side quests — abundant, Pokémon-style, and each telling part of what happened

### 5.1 The world's mystery — "The Calder Logs"
**Dr. Ruth Calder** was a geographer who, years before the Stillness, mapped the places people had stopped visiting, and noticed they were getting *thin*. When the fog came she travelled the country recording it, and left **nine field logs, one per region**, before she vanished.
- Each region's **Truth quest** ends with one log.
- In any order, the logs explain the world's rules — **one rule per log**, listed in `design_story_and_world.md` §3.1: why the fog feeds on absence, why the healing network died, why legendaries and Anchors can't be copied. The Pacific log explains what the Distortion is becoming — **the Echo** — and why it chose you.
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
| **Calder's Specimen Case** *(pass 20)* | Barataria Preserve's visitor centre | **Specimen Case** — holds Zygarde's cells and hums near one | the **cell hunt** across all 27 cities and 60 parks |
| **The Keystone** *(Decision 36)* | the Archive of the Stillness (Library of Congress), once you hold five Anchors | **Walker's Keystone** | **Mega Evolution** (`design_creatures_and_battles.md` §13a) |

### 5.3 Regional Truth quests — one per region, 4–6 steps
Each starts at the region's first-visited city and threads through all three cities and at least one park. It ends with that region's Calder log, which reveals how the region went dark (story §4a):

| Region | Truth quest | Spine | Ends with the log |
|---|---|---|---|
| New England | **The Last Light** | Relight three harbour lamps in order (Boston, Providence, Portland) and learn why the lighthouses failed first. | *The Unkept Lamps* |
| Middle Atlantic | **The Night the Grid Failed** | Restore subway power line by line; recover the transit control log; climb the Cathedral of Learning for the Thinning's first data. | *What Runs Through It* |
| South Atlantic | **The Long Summer** | Track the vine-growth records from the Archive to Atlanta's garden and Miami's tower. | *The Untended* |
| East South Central | **Hollow Voices** | Collect field recordings in Nashville, Memphis, and Louisville that capture the mines "breathing" fog. | *The Breathing Hills* |
| West South Central | **Smoke and Water** | Follow the wildfire crews' maps and the flood records in the Cabildo; a ghost-parade night in New Orleans. | *Smoke Roads* |
| East North Central | **The Frozen Winter** | Reconstruct the ice winter from the Field Museum, the Renaissance Center, and Terminal Tower — and find where the fog gathered first. | *The Ice Winter* |
| West North Central | **Storm Cellars** | Find the storm logs in the Mill City ruins, the City Museum's tunnels, and the Nelson-Atkins garden. | *Reading the Sky* |
| Mountain | **The Towns That Went First** | Ghost-town ledgers from Las Vegas, Denver, and Phoenix; why Ghosts are calm here, and why the canyons never changed. | *What Will Not Copy* |
| Pacific | **What the Fog Copies** | June Okafor's own observations: Coit Tower murals, Griffith's mirrors, and the Seattle Underground. | *The Echo* |

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
| **Real-world gated** | Unlocked by an **Explore Here** report — **access only, never cargo** (pillar 2). | "Night Walker": an Explore Here report from a famous city after dark there (the report's time, in that city's time zone) reveals a hidden Ghost trainer |
| **Move tutor** | Do a task; learn a move. | Air and Space Museum |
| **Legendary hint** | A short quest before each legendary's challenge — find runes, notes, or tracks. It also tells the player any lore requirement before they travel (`design_famous_places.md` §6). | Three rune tablets before the Regi doors |

### 5.5 How many — the abundance targets
| Kind | Target |
|---|---|
| Regional Truth quests | **9** — one per region |
| Key-item quests | **6** (§5.2) |
| City side quests | **4 per city, 6 in Las Vegas → 110**, written in `content_quest_roster.md` |
| Park side quests | **1 per park or wonder → 60**, written there too |
| Legendary hint quests | **78** — one per legendary place |
| Cross-country chains | **≥ 5**: Lost Postcards, Letters Home, Old Friends, Night Walker, **The Hundred Cells** (Zygarde) |

**Total: about 270 or more**, all written as data (§6).

---

## 6. Data and files (built in Phases 7–8)
- **`game/data/interiors/<interior id>.json`** — family, floors, the puzzle modules and their parameters, NPC ids, item spots (item numbers), the lair or Warden set piece, and the place id and door position. Layouts come from `(id, MAP_SEED)` plus authored set pieces.
- **`game/data/quests/<quest id>.json`** — steps (trigger → condition → effect), rewards (item numbers, move numbers, access flags), lore text (original), and region.
- **`game/data/lore/`** — the Calder logs, the Lost Postcards, and NPC dialogue. All original prose.
- **Engine:** `game/explore/interior_generator.gd`, `game/explore/puzzles/*.gd` (one per §3 kind), `game/quests/quest_engine.gd`, `game/ui/journal.gd` (the Walker's Journal: quests, logs, postcards).
- **Save** (a later migration): `quest_progress(quest_id, step, state)`, `interior_state(interior_id, cleared, items_json)`, `lore_found(lore_id)`.
- **Golden invariant 1 still holds:** quests and interiors are play state. The sync ingest never writes them. A real-world-gated quest only *unlocks* a step; the reward is still earned in play.
