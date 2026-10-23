# Implementation Plan — Explore Here: the Places Pack, the Phone's One Button, and the PC's Unlocks

> **Status: APPROVED by directive (2026-10-21, Decision 29).** In the human's words: "the phone app shouldn't track your location because that can be too much effort. Instead the player can open up the app whenever they are in a new place to see if the game recognizes it as a neighborhood that they haven't explored (big button that is maybe labeled as "Explore Here"). If it is a new neighborhood that is in the game, the app notifies the game that the neighborhood has been unlocked. The app should also notify the player if the city itself has been unlocked when enough neighborhoods are visited. Likewise with the national parks."
>
> **Contracts:** `design_companion_and_sync.md` (scope, places pack, protocol) and `design_privacy_and_location.md` (one reading, never kept). Built in agent guide **Items 26–28**.
>
> Every number, name, and string here is deliberate — implement as written.

**What this means for the player:**
- When you're somewhere new, you open the companion and tap **Explore Here**. The phone tells you at once: a new neighbourhood, a city revealed, a park revealed, already explored, or not on the map.
- The next time the phone and PC meet, the PC applies the same unlocks.
- The phone never tracks you. It reads your location only when you tap, checks it on the phone, and throws the reading away. Only area names ever reach the PC.

**The one idea that makes it work:** a **places pack** — the famous places' areas, cell by cell — built once per map snapshot and bundled byte-identically with both apps. The phone answers from it; the PC unlocks from it; the converter fills place stores from it. Nothing can disagree.

---

## 1. The places pack — `tools/build_places_pack.py` (Item 26)
A development-time tool. Players never run it, and nothing in either app ever queries a server.

### 1.1 The shared grid
- **New `tools/grid.py`** — a line-for-line port of `game/world/grid.gd`'s `latlon_to_wm` and cell maths (EPSG:3857, 256 WM-m cells; north is +y).
- **New golden vectors, `tools/testdata/grid_vectors.json`:** at least 40 `(lat, lon) → (wm_x, wm_y, cell_x, cell_y)` cases, including points on cell edges, negative longitudes, Alaska, Hawaii, and Puerto Rico. Use public landmark coordinates and round numbers only.
- **The same vectors are asserted by three tests:**
  - `tools/test_grid.py`;
  - `grid_test.gd` (extended);
  - the companion's new `test/grid_test.dart` (§3.2).

  A projection that drifts in any one language fails its test.

### 1.2 Inputs
- `game/config/famous_places.json`: each city's and site's `osm_boundary` relation id (spots aren't in the pack — they unlock with their city).
- **Overpass API, at the pinned date.** Every query starts `[out:json][timeout:180][date:"2026-10-01T00:00:00Z"];` — the instant matching `MAP_SNAPSHOT` (`design_famous_places.md` §7). Per place:
  - **the boundary:** `rel(<id>); out geom;`;
  - **cities, rule-1 polygons:**
    ```
    rel(<id>); map_to_area->.city;
    ( rel(area.city)["boundary"="administrative"]["admin_level"="10"]["name"];
      way(area.city)["place"~"^(neighbourhood|suburb|quarter)$"]["name"];
      rel(area.city)["place"~"^(neighbourhood|suburb|quarter)$"]["name"]; );
    out geom;
    ```
  - **cities, rule-2 points:**
    ```
    rel(<id>); map_to_area->.city;
    node(area.city)["place"~"^(neighbourhood|suburb|quarter)$"]["name"];
    out;
    ```
- **Politeness:**
  - endpoint `https://overpass-api.de/api/interpreter`, one request at a time, at least **5 s** apart;
  - `User-Agent: TenthSpring-dev/<version>`;
  - on HTTP 429 or 504, wait 60 s and retry, at most 3 times.
- **Cache:** raw responses go to `--cache-dir` (default `~/.cache/tenth_spring/overpass/`, **outside the repo**). Reruns read the cache, so a rebuild needs no network.
- **Memory:** the tool runs under memguard step `build_places_pack` (measure the budget on its first run).

### 1.3 Building each place
- **Geometry.**
  - Stitch relation members into closed rings — outers and inners, the even-odd rule — and project them with `tools/grid.py`.
  - A cell is **inside** a place when its centre is inside the boundary.
  - The pack works in cells only, so the phone and the PC test exactly the same thing.
- **Cities:**
  - **neighbourhoods** come from the three rules of `implementation_plan_famous_places.md` §8.2 (rule-1 polygons, smallest first; else the nearest rule-2 point; else 4 × 4 districts);
  - **area keys:** `osm:r<id>`, `osm:w<id>`, `osm:n<id>`, or `grid:<city id>:<floor(cx/4)>:<floor(cy/4)>`;
  - **threshold:** `T = 1` if the city has 1 neighbourhood, else `clamp(ceil(0.10 × n), 2, 5)` (Decision 22).
- **Sites:** one area, keyed by the place id, holding every inside cell.
- **Overlaps fail the build.** If any cell is inside two places, the tool prints the two place ids and exits 1, and a human decides. None is expected.
- **Waypost:** copied from `famous_places.json` (public landmark coordinates), so the phone can pick the starter city.

### 1.4 Output — `game/data/places_pack_v1.json.gz`
Canonical JSON (sorted keys, no whitespace), gzipped with mtime 0 so rebuilds are byte-identical:
```json
{
  "pack_version": 1,
  "snapshot": "261001",
  "attribution": "© OpenStreetMap contributors (ODbL)",
  "places": [
    { "id": "city:boston", "kind": "city", "name": "Boston", "region": "New England",
      "waypost": {"lat": 42.3603, "lon": -71.0580}, "threshold": 2,
      "bbox": [cx_min, cy_min, cx_max, cy_max],
      "areas": [ {"key": "osm:r123", "name": "Back Bay"}, ... ],
      "rows": [ [cy, cx0, len, area_index, cx0, len, area_index, ...], ... ] },
    { "id": "site:acadia", "kind": "site", "name": "Acadia National Park", ...,
      "areas": [ {"key": "site:acadia", "name": "Acadia National Park"} ], "rows": [...] }
  ]
}
```
*(The coordinates and names shown are illustrative.)*
- **`rows`:** run-length cells, sorted by `cy`, then by `cx0`. Runs never overlap.
- **Also written:** `game/data/places_pack_v1.sha256`, and a byte-identical copy at `companion/assets/places_pack_v1.json.gz`. A battery check fails if either copy's SHA-256 differs from the `.sha256` file.
- **Size:** the tool prints the gzipped size and fails above **4 MiB** (≈ 1 MiB expected).
- **Licence:** `game/data/PLACES_PACK_NOTICE.md` says the pack is a derived database of OpenStreetMap data, © OpenStreetMap contributors, available under the ODbL. The companion's Controls screen and the README carry the attribution.
- **Privacy:** the pack contains only the 87 public places of `famous_places.json` (27 cities and 60 sites). A battery check asserts its place ids are exactly that set. The tool never takes a user location.

### 1.5 Tests — `tools/test_build_places_pack.py`
Uses a synthetic Overpass fixture (`tools/testdata/overpass_fixture/`, made-up names and coordinates, like fixture v4):
- **Falsifying (F55):** a city with an `admin_level=9` ward covering everything, plus three neighbourhood points. The pack has **3** areas, never 1 ward.
- A `place=neighbourhood` polygon inside an `admin_level=10` polygon: the cells inside both go to the smaller one.
- Cells beyond every polygon, with no points, form `grid:` districts.
- Two overlapping places → exit 1, naming both ids.
- Two runs from the same cache → byte-identical output.
- The `rows` round-trip: decoding gives exactly the inside cells.

---

## 2. The PC reads the pack (Item 26)
1. **New `game/world/places_pack.gd`:**
   - loads `res://data/places_pack_v1.json.gz` (`FileAccess.open_compressed(…, FileAccess.COMPRESSION_GZIP)`);
   - **API:**
     - `lookup_cell(cx, cy) -> Dictionary` — `{place_id, area_key}` or `{}`, via the bbox prefilter and a binary search over rows and runs;
     - `area(area_key)` — place id, kind, and name;
     - `cells_of(area_key) -> PackedVector2Array`;
     - `areas_of(place_id)`, `threshold(place_id)`, `waypost(place_id)`, `pack_version()`;
     - `nearest_city(lat, lon)` — by Waypost ground distance, ties to the lower id. It's used **only** by migration 3 (§4.2).
   - **Export:** add `data/*.gz` to the export preset's non-resource include filter.
2. **The converter copies areas from the pack.** `tools/map_convert.py --place <id>` (and the in-game install):
   - takes the conversion unit from the pack's `bbox` (+2 cells, as before);
   - writes `areas` and `area_cells` straight from the pack;
   - deletes Item 18's neighbourhood assignment (rules a–c in `region_converter.gd`);
   - store `schema_version = '5'`, `import_state('pack_version', '1')`. The map view skips older stores (`map: skipping <file> — store schema <v>, need 5`).
3. **Test fixture:** `game/tests/fixtures/places_pack_fixture.json.gz`, built by the tool from the synthetic fixture. `region_import_test`'s v4 assertions become v5: the areas match the fixture pack exactly.
4. **Re-convert DC** from the pinned snapshot. Report the area count, `T`, and the count by rule (polygons, points, districts).

---

## 3. The companion — Explore Here (Item 27)

### 3.1 Remove (Decision 29)
- **Files:**
  - `lib/capture/` — `detector.dart`, `fuzz.dart`, `gpx_replay_source.dart`, `os_location_source.dart`, `location_source.dart`;
  - their tests (`detector_test`, `fuzz_test`, `gpx_*_test`, `os_location_source_test`);
  - the GPX fixtures;
  - the battery-debug log;
  - the scout ledger's visit list.
- **Permissions:**
  - **iOS** `Info.plist`: delete `NSLocationAlwaysAndWhenInUseUsageDescription` and `UIBackgroundModes`/`location`. Keep `NSLocationWhenInUseUsageDescription` with §3.4's rationale.
  - **Android** `AndroidManifest.xml`: delete `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, and `FOREGROUND_SERVICE_LOCATION`, plus any foreground-service declaration. Keep `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`.
- **The outbox:**
  - the Drift schema goes to version 2, and its migration **drops** `VisitOutbox` with its rows — pre-release development data, coordinates included;
  - `MetaTable` stays.

### 3.2 Add
| File | What it does |
|---|---|
| `lib/explore/grid.dart` | The same projection as `grid.gd`; passes `test/grid_test.dart` on the shared vectors (§1.1). |
| `lib/explore/places_pack.dart` | Loads `assets/places_pack_v1.json.gz` (`GZipCodec`), same lookup API as §2. |
| `lib/explore/explore_service.dart` | The one place a coordinate exists, and only in memory: one reading → lookup → result → the reading discarded. |
| `lib/explore/explore_store.dart` | Drift v2 tables: `ExploredArea(areaKey PK, placeId, firstAtMs, starter bool)`, `ExploreOutbox(seq PK autoinc, kind, placeId, areaKey nullable, tsUtcMs)`, and `meta` keys `starter_place_id` and `pack_version`. **No real-number column exists in the schema.** |
| `lib/ui/explore_screen.dart` | The main screen: the big button, the result card, and "Report to PC". |
| `lib/ui/explored_list_screen.dart` | The places explored, grouped by place, with progress. |
| `lib/ui/controls_screen.dart` | Set home, erase everything, permission status, attribution. |

### 3.3 Explore Here, step by step
1. **Permission:** `Geolocator.checkPermission()`. If denied, request once (while in use). If still denied, show `Explore Here needs your location once, only when you tap. You can allow it in Settings.` with a button to open Settings.
2. **The reading:** `Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)))`.
   - On timeout → `Couldn't find your location — try again in the open.`
   - If `position.accuracy > 100` → `Your location is too fuzzy here — try again in the open.`
   - Neither records anything.
3. **Lookup:** compute the cell; then `pack.lookupCell(cx, cy)`. **The `Position` object goes out of scope here** — it's never assigned to a field, logged, or persisted.
4. **Result:**

   | Case | Message | Recorded |
   |---|---|---|
   | Not in any place | `This spot isn't on Tenth Spring's map. The map covers 27 famous cities and 60 parks and wonders.` | nothing |
   | Area already explored | `Already explored — <area name>. <k> of <T> neighbourhoods explored in <city>.` (city) / `Already explored — <park>.` (site) | nothing |
   | New neighbourhood, threshold not reached | `New neighbourhood — <area name>, <city>! <k> of <T> to reveal the whole city.` | `ExploredArea` + outbox `explore` |
   | New neighbourhood reaching `T` | the line above, then `City revealed — <city>! You can Distort there from home.` | the same |
   | New park or wonder | `<park> revealed! You can Distort there from home.` | the same |

   - `k` counts this city's `ExploredArea` rows, including the starter city's Waypost neighbourhood (§3.5).
   - **On the PC** the same unlock happens at the next report (§4).
5. **Notifications** are in-app only — a result card plus a short vibration on new unlocks. The app sends no push and schedules no local notification.

### 3.4 The permission rationale (canonical)
`Tenth Spring checks your location once, only when you tap Explore Here or Set home. Your phone looks it up on a map of famous places and then forgets it. Only the name of the place you unlocked is sent to your own PC.` This is `NSLocationWhenInUseUsageDescription` and the in-app text (`design_privacy_and_location.md` §3).

### 3.5 Set home
1. One reading, as in §3.3 steps 1–2.
2. The nearest city by Waypost ground distance, ties to the lower id.
3. The reading is discarded.
4. Store `starter_place_id`. Mark the starter's **Waypost neighbourhood** (the area of the Waypost's cell) as an `ExploredArea` with `starter = true`. **That row is never sent** — the PC reveals it itself from the `home` event.
5. Queue an outbox `home` row naming the city.
6. Show: `Your starting city is <city>. Only its name is saved.`
7. Set home is repeatable. A new starter city adds to the old one, never replaces it (unlocks only add).

### 3.6 Report to PC — protocol v3
- **HELLO:** `{type, peerId, schemaVersion: 3, packVersion: 1, deviceToken}`.
- **BATCH rows:**
  - `{seq, kind: "explore", placeId, areaKey, tsUtcMs}`;
  - `{seq, kind: "home", placeId, tsUtcMs}`.
  - No other fields; no `bodyFix`. At most 500 rows, ascending by seq.
- **New ERROR codes:**
  - `pack_mismatch` → the phone shows `Your companion and game have different map versions — update both.`;
  - `bad_row` → `Report failed — update both apps.`
- **ACK** handling is unchanged: delete outbox rows up to `lastAppliedSeq`.
- **The Report screen** shows `<n> discoveries waiting` and `Last report: <time>`.

### 3.7 Tests
- `grid_test.dart` (the shared vectors);
- `places_pack_test.dart`: lookups for fixture points inside each area, on a cell edge, and outside;
- `explore_service_test.dart`, with a fake position source:
  - **every row of the §3.3 result table**, plus the fuzzy and timeout cases;
  - the threshold message appears exactly once;
  - an already-explored area records nothing;
- `explore_store_test.dart`:
  - **falsifying:** reflect over the Drift schema and assert that no table has a `RealColumn`;
  - the v1 → v2 migration drops `VisitOutbox`;
- `sync_test.dart`: a BATCH carries only the v3 fields (a JSON-key whitelist);
- `widget_test.dart`: the big button is on the first screen, and a tap shows the result card.

`flutter analyze` must be clean, and `flutter test` must pass under memguard.

---

## 4. The PC applies explore events (Item 28)

### 4.1 Ingest — `game/autoloads/sync_server.gd`
- **HELLO:** `schemaVersion` must be 3, else `schema_mismatch`. `packVersion` must equal `PlacesPack.pack_version()`, else `pack_mismatch`.
- **Every row is checked before anything is written.** A row fails if:
  - `kind` is not `explore` or `home`;
  - it has any key outside its kind's whitelist (so `lat`, `lon`, and `bodyFix` are refused);
  - `placeId` is unknown;
  - for `explore`, `areaKey` is not an area of `placeId`;
  - for `home`, `placeId` is not a city.

  A failing row rejects the whole BATCH with `ERROR bad_row`, rolled back.
- **Writes** (in the same transaction, still only `visit_log` — golden invariant 1):
  - `visit_log(seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind)` = `(seq, peer, areaKey or placeId, NULL, NULL, tsUtcMs, 0, kind)`;
  - `DB.insert_visit_log` must bind **SQL NULL** for missing `lat`/`lon` — today it writes `0.0` (`db.gd:462-463`).
- **`bodyFix` handling is deleted,** and so are `update_sync_peer`'s body columns.

### 4.2 Save migration 3 — no coordinates anywhere
In `db.gd`'s `MIGRATIONS`, in one transaction:
1. **Every `visit_log` row with a non-NULL `lat`:**
   - compute its cell with `Grid`;
   - if `PlacesPack.lookup_cell` finds an area, set `kind = 'explore'` and `place_id = area_key`;
   - then set `lat = NULL, lon = NULL` on **every** row.
2. **`sync_peer`:** set `last_body_lat`, `last_body_lon`, and `last_body_ts` to NULL.
3. **`meta('home_cell')`, if present:** take the cell centre's lat/lon, find `PlacesPack.nearest_city`, write `meta('starter_place', <id>)`, and delete `home_cell`. Set `base_state.home_cell_x/y` to NULL.
4. **`place_node`:** set `visit_count = 0` and `last_real_visit_at = NULL`. Which POIs you stood near is a location trace, and familiarity now counts explore days per area (`design_world_generation.md` §4).
5. **Schema version 3.**

**This amends the foundation plan's §B6 rule** ("`visit_log` … never rewritten destructively"). Decision 29 makes "no coordinates kept" the stronger rule. Rows are never dropped, and unlock state must survive: the test checks that `area_reveal` and `distort_list` are identical before and after.

### 4.3 RevealEngine v2 — `game/world/reveal_engine.gd`
- **Input:** `visit_log` rows of kind `explore` and `home`, in `(started_at, peer_id, seq)` order. Other kinds are ignored (after migration 3 they are inert).
- **`explore`:** take the area from the pack.
  - **A neighbourhood:** insert into `area_reveal` (kind `'neighbourhood'`), and put the city on `distort_list` (`'visited'`). Once `T` of the city's areas are in `area_reveal`, insert the city's own row (kind `'city'`) with `unlocked_at` = that row's time.
  - **A site:** insert the site's area (kind `'site'`), and put the site on `distort_list`.
- **`home`:**
  - put the city on `distort_list` (`'starter'`);
  - insert its Waypost neighbourhood into `area_reveal`;
  - set `meta('starter_place')` to the latest home row's city.

  Earlier starter cities stay on the list.
- **Cells:** every `area_reveal` area → `PlacesPack.cells_of(area)` → `upsert_map_cell(cx, cy, 1)` (MAX semantics; `cleared` stays `cleared`). Reading the pack, not the stores, means unlocks apply before a store is installed.
- **Deleted:** `designate_home(db, stores, places, cell)`, and every lookup through `Grid.latlon_to_cell` of a visit row.
- **Runs** as before: after each committed batch (in its own transaction), after a store install, at boot, and after a demo import. It is idempotent, and it never lowers a reveal.

### 4.4 Boot and resume — `game/main.gd`
- **Delete** `get_boot_place_id()` and every `bodyFix` read.
- **Opening a place's map view** sets `meta('last_place', <place id>)`. **Return home** deletes it.
- **At boot:** if `last_place` is set and its store is installed, open that place's map view at its Waypost. The avatar's own tile arrives in Phase 4 (`design_travel_and_time.md` §4). Otherwise open the home hub.
- The PC still asks the paired phone for a report at launch and never waits for it.

### 4.5 The demo tool — explore points
- **`tools/demo_import.py --points <file.json>`** replaces `--gpx`.
  - The file holds `[{ "lat": …, "lon": … }, …]`, plus an optional `{"home": {"lat": …, "lon": …}}`.
  - It must lie **outside the repo**; keep the existing isolation check.
- **Each point** goes through the pack lookup in Godot exactly as the phone would. It becomes an `explore` row, and its coordinate is never stored. `home` becomes a `home` row for the nearest city.
- **The DC demo profile** is rebuilt from public DC points: the National Mall, Union Station, Dupont Circle, and Capitol Hill, with home at a public point outside DC.
- **`tools/sync_e2e.py`** sends v3 rows. It asserts:
  - `visit_log` kinds and counts;
  - `area_reveal` rows;
  - **zero non-NULL REAL values across every table of the save**, scanning every column whose declared type is `REAL`;
  - and that a row carrying `lat` gets `ERROR bad_row`.

### 4.6 Tests
- **`reveal_engine_test` v2** on the fixture pack:
  - **(a) falsifying:** one `explore` row for `Old Town` → every `Old Town` cell is `known` (v1 needed coordinates);
  - **(b)** a second area → `T` reached → the city is unlocked;
  - **(c)** a site row → the whole site is revealed and on the Distort list;
  - **(d)** replaying changes nothing;
  - **(e)** a `home` row → the starter, with its Waypost neighbourhood revealed;
  - **(f)** an unknown area key is refused at ingest;
  - **(g)** `cleared` stays `cleared`.
- **`db_migration_test`:** v2 → v3 on a fixture DB with visit and corridor rows inside and outside the fixture areas, plus a `home_cell`. Afterwards:
  - no non-NULL coordinate anywhere;
  - the unlocks are identical;
  - `starter_place` is set;
  - `home_cell` is gone.
- **`sync_session_test`:** `pack_mismatch`, `schema_mismatch`, and `bad_row` (for a `lat` key, an unknown place, and an area of another place).
- **`town_map_test`:** the boot cases become "last place set and installed" vs "not set".
- **`sync_ingest_isolation_test`** stays green, unchanged.

---

## 5. Docs to update when this lands (same commits)
- `design_game_state_and_models.md` §4, §8, §9: `posTileX/Y` no longer comes from the phone; `visit_log` rows are `explore`/`home` with NULL coordinates; `meta('starter_place')` replaces `meta('home_cell')`.
- `implementation_plan_foundation.md` §B4.3–§B6: point to this plan for protocol v3 and migration 3.
- `e2e_testing_journeys.md` Journeys 1, 4, and 7 (already rewritten for Explore Here in pass 19 — check them against what was built).
- `README.md` and `master_implementation_plan.md` status lines.

## 6. The real-phone check (human, after Item 28)
On the human's own phone and PC:
1. Pair the phone.
2. Tap **Set home** — the phone names a starting city.
3. Tap **Explore Here**:
   - inside a famous place: the right message appears;
   - outside every famous place: "isn't on Tenth Spring's map".
4. Tap **Report to PC** — the PC's Town Map lights the place.
5. In the phone's Settings, the app's location access shows **While Using**. There is no "Always" option and no background location indicator.

The human reports what they saw. The agent never records where the check happened.
