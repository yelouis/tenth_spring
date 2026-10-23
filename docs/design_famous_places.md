# Famous Places — What the Map Contains, How It Unlocks, Distort Travel, and the Same Map for Everyone

This is the contract for the map's scope. It was decided by the human on 2026-10-20 (Decisions 21–26 in `ongoing_general_errors.md`), narrowing "the whole USA" to **famous places only, for now**. Since 2026-10-21, places unlock through the companion's **Explore Here** button rather than background tracking (Decision 29). The legendary table was revised the same day (§1.2). On 2026-10-22 the roster grew to Generation 8 (Decision 32), adding 30 legendary places — 24 parks and wonders and 6 city spots.

Public places are named here by their real names. **The human's own home, town, and starter city are never named in this repo** (agent guide, standing constraint 5).

---

## 0. In one paragraph
The map is made of islands: **27 famous US cities** and **60 famous parks, monuments, and natural wonders**. Everything else is fog. Your home is not on the map — it's your safehouse hub, where you heal, keep your PC box, tend your garden, and **Distort** (step through the fog) to any place you have explored in real life. On day one, the famous city nearest your home is open to you for free. You arrive at each place's **Waypost**, and you can only Distort home from there.

When you're somewhere new in real life, you open the companion and tap **Explore Here**. Inside a city, that reveals the neighbourhood you're standing in; enough neighbourhoods reveal the whole city. Inside a park, it reveals all of the park. The phone tells you on the spot, and the PC applies it at the next report.

Each region's **Warden** waits at one landmark, once you've unlocked all three of that region's cities. **82 legendary and mythical Pokémon** wait at **78 themed places**, each behind a challenge, for one decisive battle. Four more (Silvally, Cosmoem, Urshifu, Melmetal) come only by evolution.

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

### 1.2 The 78 legendary places — one legendary each, never two in one spot
Every legendary and mythical species of Generations 1–8 that can be met has its own place, themed to it and spread across the regions (7–9 per region).
- Places marked **(city)** are a landmark inside one of the 27 cities — **18** of them.
- The other **60** are islands of their own, with a Waypost at their main visitor centre (or main entrance, where there is none).

| Region | Dex | Legendary | Place | Why it fits |
|---|---|---|---|---|
| New England | 144 | Articuno | Acadia National Park (ME) | the icy North Atlantic coast |
| New England | 378 | Regice | Mount Washington State Park (NH) | the summit famous for record cold and rime ice |
| New England | 480 | Uxie | Walden Pond State Reservation (MA) | where Thoreau went to learn what the woods could teach — knowledge |
| New England | 489 | Phione | Cape Cod National Seashore (MA) | drifting tide pools and dunes |
| New England | 491 | Darkrai | Katahdin Woods and Waters National Monument (ME) | a dark-sky sanctuary — some of the darkest night skies in the East |
| New England | 788 | Tapu Fini | Boston Harbor Islands National Recreation Area (MA) | the harbour's old, honest mist, guarding the oldest light on the coast |
| New England | 891 | Kubfu | Monadnock State Park (NH) | one of the most-climbed mountains in the world — a training climb |
| New England | 898 | Calyrex | Marsh-Billings-Rockefeller National Historical Park (VT) | a farm and forest tended for well over a century — a harvest king, forgotten |
| New England | 905 | Enamorus | Arnold Arboretum, Boston **(city)** | where spring is counted tree by tree |
| Middle Atlantic | 379 | Registeel | Hot Metal Bridge, Pittsburgh **(city)** | the Steel City |
| Middle Atlantic | 385 | Jirachi | Statue of Liberty, New York **(city)** | a monument to wishes and hope |
| Middle Atlantic | 481 | Mesprit | Niagara Falls State Park (NY) | the falls of awe and honeymoons — emotion |
| Middle Atlantic | 494 | Victini | Independence Hall, Philadelphia **(city)** | victory and independence |
| Middle Atlantic | 644 | Zekrom | Thomas Edison National Historical Park (NJ) | electricity and an inventor's ideals |
| Middle Atlantic | 720 | Hoopa | Coney Island, New York **(city)** | rings, tricks, and a hundred years of illusions on the boardwalk |
| Middle Atlantic | 792 | Lunala | Cherry Springs State Park (PA) | one of the darkest skies in the East, where people come to watch the moon |
| Middle Atlantic | 801 | Magearna | The Franklin Institute, Philadelphia **(city)** | home of an automaton built around 1800 that still draws and writes |
| Middle Atlantic | 896 | Glastrier | Adirondack Park (NY) | Lake Placid's Olympic ice, twice, and the deepest winters in the East |
| South Atlantic | 145 | Zapdos | Everglades National Park (FL) | great flocks of wading birds under Florida's daily summer storms — the most lightning in the country |
| South Atlantic | 151 | Mew | Great Smoky Mountains National Park (NC/TN) | one of the most biodiverse places in the country |
| South Atlantic | 249 | Lugia | Cape Hatteras National Seashore (NC) | storms and deep water off a lighthouse coast |
| South Atlantic | 384 | Rayquaza | Wright Brothers National Memorial (NC) | the birthplace of flight |
| South Atlantic | 490 | Manaphy | Biscayne National Park (FL) | coral reefs and the open sea |
| South Atlantic | 638 | Cobalion | Lincoln Memorial, Washington DC **(city)** | justice — and a real undercroft beneath it, where stalactites grow from the concrete |
| South Atlantic | 785 | Tapu Koko | Dry Tortugas National Park (FL) | a fort on a coral island 70 miles out to sea, where the Gulf's storms cross |
| South Atlantic | 791 | Solgaleo | Kennedy Space Center (FL) | where rockets rose on fire toward the sun |
| South Atlantic | 893 | Zarude | Congaree National Park (SC) | one of the tallest forest canopies on Earth — the nearest thing to a jungle |
| East South Central | 243 | Raikou | Waterfront Park, Louisville **(city)** | the riverfront famous for "Thunder" fireworks |
| East South Central | 377 | Regirock | Cathedral Caverns State Park (AL) | a giant stalagmite called Goliath, in a cave with one of the widest mouths anywhere |
| East South Central | 383 | Groudon | Reelfoot Lake State Park (TN) | a lake made when earthquakes reshaped the land |
| East South Central | 639 | Terrakion | Mammoth Cave National Park (KY) | the world's longest cave system |
| East South Central | 648 | Meloetta | Ryman Auditorium, Nashville **(city)** | Music City |
| East South Central | 786 | Tapu Lele | Gulf Islands National Seashore (MS) | barrier islands where storm-washed survivors woke healed |
| East South Central | 894 | Regieleki | Ruby Falls (TN) | an underground waterfall lit by electric lamps since 1930 |
| East South Central | 895 | Regidrago | Red River Gorge Geological Area (KY) | sandstone arches like the spine of a sleeping dragon |
| East South Central | 897 | Spectrier | Churchill Downs, Louisville **(city)** | a shadow-swift horse at the country's most famous racetrack |
| West South Central | 146 | Moltres | Big Bend National Park (TX) | desert heat |
| West South Central | 244 | Entei | Hot Springs National Park (AR) | water heated deep in the earth |
| West South Central | 382 | Kyogre | Padre Island National Seashore (TX) | the open Gulf |
| West South Central | 386 | Deoxys | Space Center Houston **(city)** | spaceflight |
| West South Central | 640 | Virizion | Buffalo National River (AR) | Ozark forests |
| West South Central | 718 | Zygarde | Jean Lafitte National Historical Park and Preserve — Barataria Preserve (LA) | the delta, where land and water keep remaking each other |
| West South Central | 719 | Diancie | Crater of Diamonds State Park (AR) | the one diamond field in the world where anyone may dig |
| West South Central | 789 | Cosmog | McDonald Observatory (TX) | some of the darkest skies in the lower 48, under giant telescopes |
| West South Central | 802 | Marshadow | Caddo Lake State Park (TX) | a maze of bayous under moss-hung cypress, where light barely reaches the water |
| East North Central | 245 | Suicune | Cuyahoga Valley National Park (OH) | a river famously brought back clean |
| East North Central | 482 | Azelf | Isle Royale National Park (MI) | a remote Lake Superior island where wolves and moose have endured for decades — willpower |
| East North Central | 486 | Regigigas | Sleeping Bear Dunes National Lakeshore (MI) | dunes towering over Lake Michigan — a colossus at rest |
| East North Central | 641 | Tornadus | Northerly Island lakefront, Chicago **(city)** | the Windy City |
| East North Central | 649 | Genesect | Michigan Central Station, Detroit **(city)** | the Motor City's great machine hall |
| East North Central | 787 | Tapu Bulu | Apostle Islands National Lakeshore (WI) | 21 forested islands and sea caves on Lake Superior |
| East North Central | 808 | Meltan | The Flats, Cleveland **(city)** | the Cuyahoga's industrial valley, where the old mills rust |
| East North Central | 888 | Zacian | Porcupine Mountains Wilderness State Park (MI) | old-growth forest above Lake Superior, where the wolves came back |
| East North Central | 889 | Zamazenta | Pictured Rocks National Lakeshore (MI) | sandstone cliffs that stand against Lake Superior's storms like a shield |
| West North Central | 380 | Latias | Bde Maka Ska (Chain of Lakes), Minneapolis **(city)** | one of the Twin Cities' lakes |
| West North Central | 381 | Latios | Voyageurs National Park (MN) | lakes and islands to the north |
| West North Central | 493 | Arceus | Gateway Arch, St. Louis **(city)** | the gateway — the "Alpha" monument |
| West North Central | 642 | Thundurus | Badlands National Park (SD) | prairie thunderstorms |
| West North Central | 645 | Landorus | Tallgrass Prairie National Preserve (KS) | land and harvest |
| West North Central | 717 | Yveltal | Theodore Roosevelt National Park (ND) | eroded badlands where coal seams once burned underground for years |
| West North Central | 772 | Type: Null | Minuteman Missile National Historic Site (SD) | a silo built to hold a weapon in check |
| Mountain | 250 | Ho-Oh | Yellowstone National Park (WY) | the rainbow colours of Grand Prismatic Spring |
| Mountain | 483 | Dialga | Grand Canyon National Park (AZ) | two billion years of time in the rock |
| Mountain | 484 | Palkia | Arches National Park (UT) | gaps opened in space |
| Mountain | 487 | Giratina | Carlsbad Caverns National Park (NM) | a hidden world below |
| Mountain | 488 | Cresselia | Craters of the Moon National Monument (ID) | a moonscape |
| Mountain | 643 | Reshiram | White Sands National Park (NM) | white dunes |
| Mountain | 800 | Necrozma | The vault beneath Fremont Street, Las Vegas **(city)** | the city of lights — and the House's stolen light (§1.4) |
| Mountain | 807 | Zeraora | Bonneville Salt Flats (UT) | where the fastest cars on Earth raced the horizon |
| Mountain | 890 | Eternatus | Meteor Crater (AZ) | the best-preserved meteor crater on Earth |
| Pacific | 150 | Mewtwo | Alcatraz Island, San Francisco **(city)** | escape from a cell built to hold anything |
| Pacific | 251 | Celebi | Redwood National Park (CA) | ancient forest — time |
| Pacific | 485 | Heatran | Hawaiʻi Volcanoes National Park (HI) | living lava |
| Pacific | 492 | Shaymin | Mount Rainier National Park (WA) | wildflower meadows |
| Pacific | 646 | Kyurem | Glacier Bay National Park (AK) | ice |
| Pacific | 647 | Keldeo | Yosemite National Park (CA) | waterfalls |
| Pacific | 716 | Xerneas | Sequoia National Park (CA) | the largest living tree on Earth — life |
| Pacific | 721 | Volcanion | Lassen Volcanic National Park (CA) | boiling mud pots and steam vents under a sleeping volcano |

**Added 2026-10-22 (Decision 32 — Generation 8):** 30 rows — the legendaries and mythicals of Generations 6–8 that can be met.
- **Region counts** are now New England 9, Middle Atlantic 9, South Atlantic 9, East South Central 9, West South Central 9, East North Central 9, West North Central 7, Mountain 9, and Pacific 8.
- **Respect inside these places** (§6):
  - **Boston Harbor Islands:** the lair is at Boston Light, never Deer Island, where Native people were interned in 1675–76.
  - **Kennedy Space Center:** the lair is a launch gantry, never the memorial to lost astronauts.
  - **Red River Gorge:** the lair is at a natural arch, never the rock shelters that hold Native archaeology.
  - **Apostle Islands:** the lair is in the sea caves. Madeline Island, the Ojibwe's spiritual centre, isn't part of the lakeshore and isn't used.
- **The Tapu guard four US island groups, not Hawaiʻi.** They are modelled on Polynesian guardian spirits, and placing them at Native Hawaiian sacred ground would make Hawaiian religion a game prop.

**Revised 2026-10-21 (pass 19 content review):**
- **The lake trio now match their places:**
  - Uxie (knowledge) moved to Walden Pond;
  - Mesprit (emotion) to Niagara Falls;
  - Azelf (willpower) to Isle Royale.
- **Zapdos moved to the Everglades,** and Theodore Roosevelt National Park left the map. The West North Central badlands already hold Thundurus, and Florida's storms suit a lightning bird better. South Atlantic now has 6 legendaries and West North Central 5.
- **Darkrai moved to Katahdin Woods and Waters,** and Salem Maritime left the map. Salem is famous for the 1692 witch trials, in which innocent people were executed. A nightmare Pokémon there would play a real tragedy for spooks (story §9: never mock real places or people).
- **Regirock moved to Cathedral Caverns,** and Russell Cave left the map. Russell Cave preserves 10,000 years of Native American life, and a "rune door" dungeon there would turn real Native heritage into a fantasy ruin.

*The species, places, and themes are starting content, like the spawn tables. The human may swap any row; keep the rule "one legendary per place".*

### 1.4 Backstories of the Generation 6–8 legendaries (Decision 32)
Each is told the way survivors tell it. The lair challenges are `design_interiors_and_quests.md` §4.3, and the lore requirements are §6.

**New England**
- **Tapu Fini — Boston Harbor Islands.** The harbour fog was here long before the Distortion — old, honest fog, the sailors say. On the first fog night, Boston Light kept burning when every other lamp on the coast went out, and the grey turned back at its edge. Something in the islands' mist guards the oldest light in the country.
- **Kubfu — Monadnock.** People climbed Mount Monadnock by the tens of thousands every year. After the Stillness, one small Pokémon kept climbing it every day, alone. Train with it, and it will choose a path: the way of shadow, or the way of water.
- **Calyrex — Marsh-Billings-Rockefeller.** These fields and woods were tended carefully for well over a century, and the old story says the harvest was kept by a small king who rode a great horse. When people stopped walking the fields, the king faded, as the fog says every forgotten thing fades. Bring it a harvest, and a steed, and it may remember who it was.
- **Enamorus — Arnold Arboretum.** For ten winters the fog held, and then, this spring, it pulled back. In the arboretum's archive is an old story of a spirit who brings the spring and won't stay where she isn't loved. She comes only after the three storm-spirits of the plains are settled.

**Middle Atlantic**
- **Hoopa — Coney Island.** Some nights the rides turn with nobody at the controls. Things vanish from the boardwalk and turn up in other cities: a carousel horse in Chicago, a Ferris-wheel car in a Pittsburgh river. Whoever is doing it is laughing.
- **Lunala — Cherry Springs.** Stargazers kept coming to the dark field after the Stillness, because it was the last place they could still see the stars. On moonless nights a great winged shape crosses the sky and the stars blink out behind it. The people on the field say it comes to watch with them.
- **Magearna — the Franklin Institute.** The museum's automaton was built around 1800 to draw and write. After the Stillness it started drawing new pictures: maps of places nobody had walked, and a heart-shaped gear. Its keepers say its soul is a gear gone missing, and that something far older is waiting in the machine.
- **Glastrier — Adirondacks.** Lake Placid held the Winter Olympics twice. Now the old bobsled run is a river of ice that never thaws, and something heavy gallops it at night, leaving frost hoofprints a hand deep. It comes only for food that grows in frost.

**South Atlantic**
- **Tapu Koko — Dry Tortugas.** The fort on the coral island lost its lights the first night. But lightning has struck the same parapet every evening since, at the same minute. The last supply boat's crew say a guardian keeps watch over the Gulf, curious about anyone who lands.
- **Solgaleo — Kennedy Space Center.** The last rocket on the pad never launched. Survivors on the Space Coast say that at noon the gantry glows white-hot and a great shape paces the pad, as if waiting for the sun.
- **Zarude — Congaree.** The floodplain forest went wild after the Stillness. A troop of vine-swinging Pokémon moved in, and they don't like visitors. The old rangers swear their leader once raised a lost child, and might be persuaded to trust you.

**East South Central**
- **Tapu Lele — Gulf Islands.** Survivors who washed up on the barrier islands after the storms woke healed, with glittering scales in their hair. A guardian of the islands scatters them — and plays with anyone who takes no more than they need.
- **Regieleki — Ruby Falls.** The waterfall deep in Lookout Mountain has been lit by electric lamps since 1930. The lamps never went out after the Stillness, because something in the rock is making the current. Its door is marked with the old symbols.
- **Regidrago — Red River Gorge.** The sandstone arches along the ridge look like the spine of a sleeping dragon. Climbers found a chamber behind one of them, sealed with the same symbols as the giants' doors and carved around a dragon's head.
- **Spectrier — Churchill Downs.** The track's gates still open every morning, because Hank Abernathy opens them. Some mornings a horse made of shadow runs the course faster than any horse ever has, and leaves no hoofprints. It comes only for food that grows in shade.

**West South Central**
- **Zygarde — Barataria Preserve.** The delta is always remaking itself: land sinks, and new land rises from the silt. Calder believed something keeps the balance. She found the same green cells in marsh water from Louisiana to Maine. Gather enough of them, and what they belong to wakes.
- **Diancie — Crater of Diamonds.** The one diamond field in the world where anyone could dig and keep what they found. After the Stillness, diggers came for food, not gems — and some found stones that glowed pink in the dark. Something under the field is still making them.
- **Cosmog — McDonald Observatory.** The astronomers' last log records a "nebula on the mirror": a cloud of light that sat on the great telescope's glass and wouldn't wipe off. It's still there, small and curious. Taken somewhere it trusts, it grows into something far greater.
- **Marshadow — Caddo Lake.** In the bayous under the moss, your shadow sometimes moves before you do. The fishermen say something lives in the shade and learns by watching: every move it sees, it can do. It has been watching the fog longer than anyone.

**East North Central**
- **Tapu Bulu — Apostle Islands.** On these islands the forest grows back over anything left untended faster than anywhere else on the lakes. The ferry crews heard bells in the woods. A guardian lives there, lazy until something threatens its forest.
- **Meltan — the Flats, Cleveland.** The old mills in the Flats are rusting away faster than they should, with bolts and beams vanishing overnight. The culprits are small, nut-headed, and made of liquid metal. Feed one enough, and the metal remembers what it wants to become.
- **Zacian — Porcupine Mountains.** The wolves came back to the old forest above Lake Superior in the years before the Stillness. Since then, people lost in the snow have been led out by a blue wolf with a blade of light in its jaws.
- **Zamazenta — Pictured Rocks.** The painted cliffs have stood against Lake Superior's storms for ten thousand years. When the fog came across the ice, it stopped at the cliffs, and a red wolf stood on the rim all winter like a shield. The sword and the shield were always a pair.

**West North Central**
- **Yveltal — Theodore Roosevelt National Park.** In the badlands, coal seams burned underground for years. When the fog came, every fire went out at once, and the ground went cold and grey. Ranchers tell of a red shadow over the buttes that drains the colour from whatever it passes. Nothing grows where it sleeps — yet the fog won't touch that ground either.
- **Type: Null — Minuteman Missile.** In the years of the Thinning, a research team used an empty missile silo to build "a Pokémon to fight what comes out of the thin places": a chimera, masked so its power could never run away with it. The team never came back up. What they built is still down there, waiting for someone to trust.

**Mountain**
- **Necrozma — the vault beneath Fremont Street.** The Glow's lights never went out, and now we know why. Deep under the canopy, the House keeps a creature made of hunger for light, and feeds it the light of every desert town it can reach. The towns went dark one by one. The creature is starving, and furious (`design_story_and_world.md` §4b).
- **Zeraora — Bonneville.** On the salt flats where the fastest cars on Earth raced the horizon, storms come in fast and white. Survivors have seen a streak of lightning running on four legs, outrunning the storm front, faster than anything ever timed there.
- **Eternatus — Meteor Crater.** A falling star made the crater fifty thousand years ago, and Calder's notes say the star wasn't empty. Something sleeps under the crater floor: a darkness so old that the fog itself won't go near it. Only the sword and the shield of the north are said ever to have faced it.

**Pacific**
- **Xerneas — Sequoia.** The oldest trees in the Sierra stopped dropping their needles the winter the fog came, as if something among them had decided to keep living for everyone. Rangers found a tree that hadn't been there before, in a grove they knew by heart — and in the right light it has antlers.
- **Volcanion — Lassen.** Lassen's boiling pools never cooled. Survivors who camped there woke with their fires doused and their gear steaming, and the park's Pokémon untouched by the fog. Something there protects the wild from people, and isn't sure about you yet.

**And the Ultra Beasts** (Nihilego, Buzzwole, Pheromosa, Xurkitree, Celesteela, Kartana, Guzzlord, Poipole, Naganadel, Stakataka, Blacephalon) aren't copies of anything here. They come through the very thinnest fog, and only once Necrozma — which drank the light that kept those doors shut — has been caught or defeated. They appear only in Distortion Fields (`design_encounters_and_haunted_zones.md` §3a).

### 1.3 Everything else
Not on the map, for now. Cells outside every famous place are never drawn and never offered for download. Explore Here outside every famous place says so and records nothing (Decision 29).

---

## 2. Home — the hub
- **Home is not on the map.** It's a hub screen: your house, with **full healing**, the **PC box**, the **berry garden**, and the **Distort door**.
- **The real home location** is used once, on the phone, for one thing only: choosing the **starter city** (§3.1). The companion's **Set home** takes one reading, picks the nearest famous city on the phone, and sends only that city's id. **Home's location never leaves the phone** (`design_privacy_and_location.md` §1).
- **The stranded rule becomes:** away from home, in any place, you have only the party and bag you brought. Healing and the PC box are at home. You get home only through a Waypost (§4) — or by blacking out.

---

## 3. Unlocking
**"Exploring" always means an Explore Here report** (Decision 29): one tap on the companion, one location reading, looked up on the phone in the bundled **places pack** (`design_companion_and_sync.md` §1.1). The pack is built from the pinned snapshot, and the PC uses the identical file, so the phone's answer and the PC's unlock always agree. In-game travel never unlocks a place; it only clears it, under the two-fog model.

### 3.1 The starter city
On day one, the famous city whose Waypost is nearest home — by ground distance, ties to the lower place id, worked out on the phone — is on your Distort list. Its **Waypost neighbourhood** is revealed (`known`), so you have ground to explore. The rest of it opens as you explore it for real.

### 3.2 Cities: neighbourhoods, then the whole city
- **Neighbourhoods** come from OpenStreetMap inside the city's boundary (F55, 2026-10-21):
  1. named `boundary=administrative` areas at `admin_level` **10** — never 9, which in many cities means wards or council districts (DC's 8 wards);
  2. else areas around the city's named `place=neighbourhood|suburb|quarter` points, each cell going to its nearest point;
  3. else ~1 km districts of 4 × 4 cells.

  The result is stored in the places pack (`implementation_plan_famous_places.md` §3).
- **An Explore Here inside a neighbourhood reveals all of it** (Decision 29, replacing Decision 21's "any movement").
- **The whole city is revealed** once `T` of its neighbourhoods are: `T = 1` if the city has 1 neighbourhood, else `clamp(ceil(0.10 × n), 2, 5)` (Decision 22 = A).
- **The first Explore Here anywhere in a city** also puts it on your Distort list.

### 3.3 Legendary places outside cities
An Explore Here anywhere inside the place's boundary reveals the **whole place** and puts it on your Distort list.

### 3.4 Unlocking only ever adds
Nothing is ever re-locked, and reveal states never decrease.

---

## 4. Distort travel
- **From home,** Distort for free to any place on your Distort list. You arrive at its **Waypost**.
- **From a place,** Distort home **only at that place's Waypost**. Blacking out also sends you home, under the normal blackout rules.
- **Between two places,** you go through home: Distort home from the first place's Waypost, then out to the second.
- **Session start:** where the last session ended — at home, or on the tile where you quit inside a place (`design_travel_and_time.md` §4). The phone never moves you, so quitting is never a free trip home.
- **Distort costs no game time** and is never blocked by night.
- **Inside a place,** movement follows `design_travel_and_time.md`: the 15 mph clock, terrain, day and night.
- **In the story** (`design_story_and_world.md` §2.6), Walkers can step through the Distortion to firm ground they have walked and marked in their Ledger. That's why you can't Distort somewhere you've never been.

---

## 5. Wardens (Decision 18 = B, refined by Decision 26)
- **When:** a region's Warden can be met only after **all three** of that region's cities are fully unlocked (§3.2).
- **Where:** each Warden waits at one fixed landmark. Their trials and Anchors are as in `design_story_and_world.md` §4.
- **Levels:** a fixed level-75 team, built like a competitive team (Decision 35).
- **The finale needs all nine Anchors** — so the story requires exploring all 27 cities in real life, enough neighbourhoods in each.

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
- **The lair.** Each legendary waits at a fixed lair inside its place, behind a **challenge** — a maze or puzzle you must clear in-game to reach it. When the place is a building or structure, the challenge is that building's interior (`design_interiors_and_quests.md` §1, §4).
- **The same for everyone.** Lair layouts are generated from `(dex number, the global map seed)`, so every player meets the same challenge.
- **Each legendary has its own challenge,** and each has an in-world reason. The Distortion can't copy a legendary, so it crowds around one, and the ground near it warps into the shape of what that legendary *is*: ice around Articuno, slipping time around Dialga. The full table of 48 is `design_interiors_and_quests.md` §4.3.
- **Respect inside a place.** A lair is never on sacred or memorial ground within its place. For example, Heatran's lair is an old lava tube, never the summit crater, which is sacred to Native Hawaiians.
- **Lore requirements** — some legendaries come only after others, as in their legends. Every requirement is "**caught or defeated**" (either ends a legendary), so no choice can lock a player out:

  | Legendary | Appears once | Why |
  |---|---|---|
  | Lugia | Articuno, Zapdos, and Moltres are each caught or defeated | it is the guardian of the three birds |
  | Ho-Oh | Raikou, Entei, and Suicune are each caught or defeated | it raised the three beasts, and comes to see what became of them |
  | Rayquaza | Kyogre and Groudon are caught or defeated | it descends only to calm the sea and the land |
  | Giratina | Dialga and Palkia are caught or defeated | the third of the trio, banished below |
  | Kyurem | Reshiram and Zekrom are caught or defeated | the empty husk left when the first dragon split in two |
  | Regigigas | Regirock, Regice, and Registeel are caught or defeated | it wakes only when its three are freed. *Fixed 2026-10-21:* this rule used to say "in your party", which locked out anyone who had defeated a Regi instead of catching it |
  | Keldeo | Cobalion, Terrakion, and Virizion are caught or defeated | it must prove itself to the Swords |
  | Darkrai | you hold the **Moon Feather**, given at Cresselia's lair once Cresselia is caught or defeated | only the Moon Feather lets you sleep through its nightmares |
  | Shaymin | you've grown and harvested a berry in your home garden | it comes only to someone who tends something |
  | Arceus | you hold all nine Anchors | the Alpha answers only to someone who has held the whole country |
  | Eternatus | Zacian and Zamazenta are caught or defeated | only the sword and the shield can stand against the darkest day |
  | Enamorus | Tornadus, Thundurus, and Landorus are caught or defeated | the fourth force of nature comes once the three storms are settled |
  | Calyrex | Glastrier or Spectrier is caught or defeated, and you bring a harvest from your home garden | a king needs a steed — and someone who still tends a field |
  | Glastrier | you've grown a **frost root** in your home garden | it comes only for food that grows in frost |
  | Spectrier | you've grown a **shade root** in your home garden | it comes only for food that grows in shade |
  | Zygarde | you've found **50 of its 100 cells**, scattered across the country (all 100 give its complete form) | its body is spread through the land it guards |
  | Magearna | you've found the **four gears** of its heart, across the Middle Atlantic | its soul is the gear that went missing |
  | Necrozma | you've uncovered the House's vault (the quest "The Light Bill") | it is locked away until someone learns the Glow's secret |
  | Marshadow | you've beaten three Hollow Trainers | it learns from copies, and only shows itself to someone who has beaten one |
  | Volcanion | you've cleansed a haunted zone | it trusts only someone who has protected the Pokémon of a place |

  The legendary hint quests (`design_interiors_and_quests.md` §5.4) tell the player each requirement before they make the trip.
- **Legendaries met by evolution** (Decision 32): Type: Null evolves into **Silvally** by friendship; Cosmog into **Cosmoem** at level 43, then at level 53 into Solgaleo by day or Lunala by night (both also wait at their own places); Kubfu into **Urshifu** by clearing one of its two trials, the Shadow or the Tide (§1.4); Meltan into **Melmetal** at level 48. These four count for the Pokédex when obtained this way.
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
One entry per place — the 27 cities, the 60 legendary islands, and the 18 legendary spots inside cities (105 entries):

| Field | Meaning |
|---|---|
| `id` | A stable slug, e.g. `"city:boston"`, `"site:acadia"`, `"spot:alcatraz"` |
| `kind` | `"city"`, `"site"`, or `"spot"` |
| `name` | The public name |
| `region` | One of the 9 Census divisions |
| `geofabrik` | The region path, e.g. `"north-america/us/massachusetts"` |
| `osm_boundary` | `"r<id>"` — the boundary relation (cities and sites); `"w<id>"` for a site mapped only as a closed way (Decision 32 adds several small sites) |
| `waypost` | `{name, lat, lon}` — city hall, or the site's main visitor centre or entrance (sites and cities) |
| `legendary_dex` | The legendary here (sites and spots) |
| `requires` | Optional, sites and spots: the lore requirement from §6. An object whose keys must **all** hold: `dex_all` (list — each caught or defeated), `dex_any` (list — at least one), `item` (`"moon_feather"`), `flag` (`"garden_harvested"`, `"frost_root"`, `"shade_root"`), `quest` (`"the_light_bill"`), `cells` (Zygarde cells found), `gears` (Magearna's), `anchors`, `hollow_wins`, `zones_cleansed`. Example: Calyrex is `{"dex_any": [896, 897], "flag": "garden_harvested"}` |
| `city` | The city id (spots only) |
| `warden` | `{name, type, landmark: {name, lat, lon}}` (one city per region) |
| `interiors` | `[{id, name, family, purposes, door: {lat, lon}}]` — the place's enterable famous buildings (`design_interiors_and_quests.md` §4), door at the public entrance |

All coordinates are of **public landmarks**, never the human's. Ids and coordinates are filled in by agent guide Item 17 and reviewed by the human.
