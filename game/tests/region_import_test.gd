extends Node

# region_import_test.gd — Region Import & Map Store Verification Test
# Contract: docs/implementation_plan_world_generation.md §5.2-§5.3 & docs/agent_execution_guide.md §6.5

const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const Grid := preload("res://world/grid.gd")
const MapConstants := preload("res://world/map_constants.gd")

const GOLDEN_CANONICAL_HASH: String = "fb7d26d6189721ed0b0652e9a69a0a92d0b4e105e904d5a303d8b34544bb368e"
const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const FIXTURE_CONFIG: String = "res://tests/fixtures/famous_places_fixture.json"
const TEST_DB_PATH: String = "user://test/map_data/region_import_test.db"

func run_test() -> bool:
	_cleanup()

	# ---------------------------------------------------------
	# 1. Full Uninterrupted Conversion Test
	# ---------------------------------------------------------
	var conv := RegionConverter.new()
	var res := conv.convert(FIXTURE_PBF, TEST_DB_PATH)

	if not res.get("ok", false):
		push_error("Full conversion failed: %s" % res.get("error", "unknown"))
		_cleanup()
		return false

	var store := MapStore.new(TEST_DB_PATH)
	if not store.open_store(false):
		push_error("Failed to open converted store: %s" % store.last_error)
		_cleanup()
		return false

	# Verify schema version 4
	if store.get_state("schema_version") != "4":
		push_error("Expected schema_version '4', got '%s'" % store.get_state("schema_version"))
		store.close()
		_cleanup()
		return false

	# Verify counts: 15 poly (incl. Temple Whole with building=yes + building:part=no), 14 line, 4 place_nodes
	var bp_whole_rows := store._rows("SELECT count(*) as c FROM features_poly WHERE name = 'Temple Whole';")
	if int(bp_whole_rows[0]["c"]) != 1:
		push_error("[falsifier] Expected 'Temple Whole' (building=yes + building:part=no) to be stored, got %d" % int(bp_whole_rows[0]["c"]))
		store.close()
		_cleanup()
		return false

	var bp_part_rows := store._rows("SELECT count(*) as c FROM features_poly WHERE name IN ('Temple Part Only', 'Temple Both Part');")
	if int(bp_part_rows[0]["c"]) != 0:
		push_error("Expected building:part=yes ways to be excluded, got %d" % int(bp_part_rows[0]["c"]))
		store.close()
		_cleanup()
		return false

	var poly_count: int = int(store._rows("SELECT count(*) as c FROM features_poly;")[0]["c"])
	var line_count: int = int(store._rows("SELECT count(*) as c FROM features_line;")[0]["c"])
	var node_count: int = int(store._rows("SELECT count(*) as c FROM place_nodes;")[0]["c"])

	if poly_count != 15:
		push_error("Expected 15 features_poly, got %d" % poly_count)
		store.close()
		_cleanup()
		return false

	if line_count != 14:
		push_error("Expected 14 features_line, got %d" % line_count)
		store.close()
		_cleanup()
		return false

	if node_count != 4:
		push_error("Expected 4 place_nodes, got %d" % node_count)
		store.close()
		_cleanup()
		return false

	# Verify polygon kinds
	var poly_kinds := store._rows("SELECT DISTINCT kind FROM features_poly ORDER BY kind;")
	var kinds_list: Array[String] = []
	for r in poly_kinds:
		kinds_list.append(r["kind"])
	if kinds_list != ["building", "cemetery", "forest", "park", "parking", "residential", "water"]:
		push_error("Unexpected polygon kinds: %s" % str(kinds_list))
		store.close()
		_cleanup()
		return false

	# Verify line kinds
	var line_kinds := store._rows("SELECT DISTINCT kind FROM features_line ORDER BY kind;")
	var line_kinds_list: Array[String] = []
	for r in line_kinds:
		line_kinds_list.append(r["kind"])
	if line_kinds_list != ["coastline", "path", "rail", "road", "waterway"]:
		push_error("Unexpected line kinds: %s" % str(line_kinds_list))
		store.close()
		_cleanup()
		return false

	# Verify cell_flags table exists and has sea flags
	var flags_rows := store._rows("SELECT count(*) as c FROM cell_flags;")
	if flags_rows.is_empty() or int(flags_rows[0]["c"]) == 0:
		push_error("cell_flags table missing or empty")
		store.close()
		_cleanup()
		return false

	# Verify absent features: tunnel way and construction polygon
	var tunnel_rows := store._rows("SELECT count(*) as c FROM features_line WHERE cell_x = 4 AND cell_y = 4 AND subkind = 'residential';")
	if int(tunnel_rows[0]["c"]) != 0:
		push_error("Tunnel way should be absent from features_line, got %d" % int(tunnel_rows[0]["c"]))
		store.close()
		_cleanup()
		return false

	var const_rows := store._rows("SELECT count(*) as c FROM features_poly WHERE subkind = 'construction' OR kind = 'construction';")
	if int(const_rows[0]["c"]) != 0:
		push_error("Construction polygon should be absent from features_poly, got %d" % int(const_rows[0]["c"]))
		store.close()
		_cleanup()
		return false

	# Verify boundary-straddling building is stored once, unclipped, in anchor cell (5, 4)
	var bm_rows := store._rows("SELECT cell_x, cell_y, kind, subkind, name, geom_rings FROM features_poly WHERE name = 'Boundary Market';")
	if bm_rows.size() != 1:
		push_error("Expected Boundary Market to appear once, got %d times" % bm_rows.size())
		store.close()
		_cleanup()
		return false
	if bm_rows[0]["cell_x"] != 5 or bm_rows[0]["cell_y"] != 4:
		push_error("Boundary Market expected anchor cell (5, 4), got (%d, %d)" % [bm_rows[0]["cell_x"], bm_rows[0]["cell_y"]])
		store.close()
		_cleanup()
		return false
	var bm_rings := MapStore.unpack_rings(bm_rows[0]["geom_rings"])
	if bm_rings.size() != 1 or bm_rings[0].size() != 5:
		push_error("Boundary Market expected 1 ring with 5 vertices (closed 4 corners) unclipped, got %d rings / %d verts" % [bm_rings.size(), bm_rings[0].size() if bm_rings.size() > 0 else 0])
		store.close()
		_cleanup()
		return false

	# Verify multipolygon lake has 2 rings (outer lake + inner island)
	var lake_rows := store._rows("SELECT geom_rings FROM features_poly WHERE kind = 'water';")
	if lake_rows.is_empty():
		push_error("Water polygon missing")
		store.close()
		_cleanup()
		return false
	var lake_rings := MapStore.unpack_rings(lake_rows[0]["geom_rings"])
	if lake_rings.size() != 2:
		push_error("Expected 2 rings for multipolygon lake (outer + inner), got %d" % lake_rings.size())
		store.close()
		_cleanup()
		return false

	# Verify golden canonical dump hash
	var canonical_hash := store.canonical_dump_sha256()
	if canonical_hash != GOLDEN_CANONICAL_HASH:
		push_error("Golden canonical hash mismatch: expected %s, got %s" % [GOLDEN_CANONICAL_HASH, canonical_hash])
		store.close()
		_cleanup()
		return false

	store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 2. Checkpoint Resume Test: Stop after Pass 1 -> Resume
	# ---------------------------------------------------------
	var conv_pass1 := RegionConverter.new()
	conv_pass1.stop_after_pass = 1
	var res_p1 := conv_pass1.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_p1.get("ok", false) or res_p1.get("stopped_after_pass", 0) != 1:
		push_error("Stop after pass 1 failed: %s" % str(res_p1))
		_cleanup()
		return false

	var conv_resume1 := RegionConverter.new()
	var res_r1 := conv_resume1.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_r1.get("ok", false) or res_r1.get("canonical_hash", "") != GOLDEN_CANONICAL_HASH:
		push_error("Resume after pass 1 failed or hash mismatch: %s" % str(res_r1))
		_cleanup()
		return false

	_cleanup()

	# ---------------------------------------------------------
	# 3. Checkpoint Resume Test: Stop after Pass 2 -> Resume
	# ---------------------------------------------------------
	var conv_pass2 := RegionConverter.new()
	conv_pass2.stop_after_pass = 2
	var res_p2 := conv_pass2.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_p2.get("ok", false) or res_p2.get("stopped_after_pass", 0) != 2:
		push_error("Stop after pass 2 failed: %s" % str(res_p2))
		_cleanup()
		return false

	var conv_resume2 := RegionConverter.new()
	var res_r2 := conv_resume2.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_r2.get("ok", false) or res_r2.get("canonical_hash", "") != GOLDEN_CANONICAL_HASH:
		push_error("Resume after pass 2 failed or hash mismatch: %s" % str(res_r2))
		_cleanup()
		return false

	_cleanup()

	# ---------------------------------------------------------
	# 4. Equivalence Test (falsifying): Clip covering full fixture
	# Canonical dump hash MUST be identical to unclipped run.
	# ---------------------------------------------------------
	var full_clip := Rect2(768.0, 768.0, 3072.0, 768.0)
	var conv_eq := RegionConverter.new()
	var res_eq := conv_eq.convert(FIXTURE_PBF, TEST_DB_PATH, full_clip)
	if not res_eq.get("ok", false):
		push_error("Full clip conversion failed: %s" % res_eq.get("error", "unknown"))
		_cleanup()
		return false

	var eq_store := MapStore.new(TEST_DB_PATH)
	if not eq_store.open_store(false):
		push_error("Failed to open eq store: %s" % eq_store.last_error)
		_cleanup()
		return false

	var eq_hash := eq_store.canonical_dump_sha256()
	if eq_hash != GOLDEN_CANONICAL_HASH:
		push_error("Clip equivalence hash mismatch: expected %s, got %s" % [GOLDEN_CANONICAL_HASH, eq_hash])
		eq_store.close()
		_cleanup()
		return false

	if eq_store.get_state("clip") != "1":
		push_error("Expected clip state '1', got '%s'" % eq_store.get_state("clip"))
		eq_store.close()
		_cleanup()
		return false

	var eq_cov: Variant = eq_store.get_coverage_box()
	if eq_cov == null:
		push_error("Expected non-null coverage box in clipped store")
		eq_store.close()
		_cleanup()
		return false

	eq_store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 5. Partial Clip Test: West half
	# East-only building absent, crossing road present and whole, lake present
	# ---------------------------------------------------------
	var west_clip := Rect2(1000.0, 1000.0, 350.0, 600.0)
	var conv_west := RegionConverter.new()
	var res_west := conv_west.convert(FIXTURE_PBF, TEST_DB_PATH, west_clip)
	if not res_west.get("ok", false):
		push_error("West clip conversion failed: %s" % res_west.get("error", "unknown"))
		_cleanup()
		return false

	var west_store := MapStore.new(TEST_DB_PATH)
	if not west_store.open_store(false):
		push_error("Failed to open west store: %s" % west_store.last_error)
		_cleanup()
		return false

	# East-only building (Maple House in cell (5, 4)) must be absent
	var b2_rows := west_store._rows("SELECT count(*) as c FROM features_poly WHERE name = 'Maple House';")
	if int(b2_rows[0]["c"]) != 0:
		push_error("Partial clip failed: east-only building 'Maple House' should be absent")
		west_store.close()
		_cleanup()
		return false

	# West building (City Hall in cell (4, 4)) must be present
	var b1_rows := west_store._rows("SELECT count(*) as c FROM features_poly WHERE name = 'City Hall';")
	if int(b1_rows[0]["c"]) != 1:
		push_error("Partial clip failed: west building 'City Hall' in cell (4, 4) should be present")
		west_store.close()
		_cleanup()
		return false

	# Boundary-straddling building (Boundary Market in cell (5, 4)) must be present (its nodes are in [1260, 1300] <= 1350)
	var bm_clipped := west_store._rows("SELECT count(*) as c FROM features_poly WHERE name = 'Boundary Market';")
	if int(bm_clipped[0]["c"]) != 1:
		push_error("Partial clip failed: Boundary Market should be present")
		west_store.close()
		_cleanup()
		return false

	# Crossing road (Lakeside Trail in cell (5, 5)) has first node inside (x=1296) and rest outside;
	# must be present and whole (all 4 vertices preserved)
	var r4_rows := west_store._rows("SELECT geom_pts FROM features_line WHERE cell_x = 5 AND cell_y = 5 AND kind = 'path';")
	if r4_rows.is_empty():
		push_error("Partial clip failed: crossing road in cell (5, 5) should be present")
		west_store.close()
		_cleanup()
		return false
	var r4_pts := MapStore.unpack_pts(r4_rows[0]["geom_pts"])
	if r4_pts.size() != 4:
		push_error("Partial clip failed: crossing road should be whole (4 pts), got %d" % r4_pts.size())
		west_store.close()
		_cleanup()
		return false

	# Multipolygon lake has outer ring node inside (x=1312) and inner ring outside;
	# lake relation must be kept with both rings
	var lake_rows_w := west_store._rows("SELECT geom_rings FROM features_poly WHERE kind = 'water';")
	if lake_rows_w.is_empty():
		push_error("Partial clip failed: lake should be present when one member way has node inside")
		west_store.close()
		_cleanup()
		return false
	var lake_rings_w := MapStore.unpack_rings(lake_rows_w[0]["geom_rings"])
	if lake_rings_w.size() != 2:
		push_error("Partial clip failed: lake should have both rings (outer + inner), got %d" % lake_rings_w.size())
		west_store.close()
		_cleanup()
		return false

	west_store.close()
	_cleanup()

	# When clip boundary is strictly west of cell 5 (x < 1280), lake has no nodes inside and must be absent
	var strict_west_clip := Rect2(1000.0, 1000.0, 270.0, 600.0)
	var conv_sw := RegionConverter.new()
	var res_sw := conv_sw.convert(FIXTURE_PBF, TEST_DB_PATH, strict_west_clip)
	if not res_sw.get("ok", false):
		push_error("Strict west clip failed: %s" % res_sw.get("error", "unknown"))
		_cleanup()
		return false

	var sw_store := MapStore.new(TEST_DB_PATH)
	if not sw_store.open_store(false):
		push_error("Failed to open strict west store: %s" % sw_store.last_error)
		_cleanup()
		return false

	var sw_lake := sw_store._rows("SELECT count(*) as c FROM features_poly WHERE kind = 'water';")
	if int(sw_lake[0]["c"]) != 0:
		push_error("Strict west clip failed: lake should be absent when no member nodes inside")
		sw_store.close()
		_cleanup()
		return false

	sw_store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 6. Empty Clip Test: Rectangle in empty ocean
	# 0 features, coverage recorded, exits 0
	# ---------------------------------------------------------
	var ocean_clip := Rect2(0.0, 0.0, 100.0, 100.0)
	var conv_ocean := RegionConverter.new()
	var res_ocean := conv_ocean.convert(FIXTURE_PBF, TEST_DB_PATH, ocean_clip)
	if not res_ocean.get("ok", false):
		push_error("Empty ocean clip conversion failed: %s" % res_ocean.get("error", "unknown"))
		_cleanup()
		return false

	var ocean_store := MapStore.new(TEST_DB_PATH)
	if not ocean_store.open_store(false):
		push_error("Failed to open ocean store: %s" % ocean_store.last_error)
		_cleanup()
		return false

	var o_poly: int = int(ocean_store._rows("SELECT count(*) as c FROM features_poly;")[0]["c"])
	var o_non_coast: int = int(ocean_store._rows("SELECT count(*) as c FROM features_line WHERE kind != 'coastline';")[0]["c"])
	var o_node: int = int(ocean_store._rows("SELECT count(*) as c FROM place_nodes;")[0]["c"])
	if o_poly != 0 or o_non_coast != 0 or o_node != 0:
		push_error("Empty ocean clip expected 0 features, got %d poly, %d non-coast line, %d nodes" % [o_poly, o_non_coast, o_node])
		ocean_store.close()
		_cleanup()
		return false

	if ocean_store.get_state("clip") != "1":
		push_error("Empty ocean clip expected clip='1', got '%s'" % ocean_store.get_state("clip"))
		ocean_store.close()
		_cleanup()
		return false

	if ocean_store.get_coverage_box() == null:
		push_error("Empty ocean clip expected recorded coverage box, got null")
		ocean_store.close()
		_cleanup()
		return false

	ocean_store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 7. Schema v4 Place Stores Verification (Fixture Places)
	# ---------------------------------------------------------
	var city_db := TEST_DB_PATH + "_city.db"
	_cleanup_path(city_db)
	var conv_city := RegionConverter.new()
	var res_city := conv_city.convert(FIXTURE_PBF, city_db, null, null, "city:fixture-city", FIXTURE_CONFIG)
	if not res_city.get("ok", false):
		push_error("Fixture city conversion failed: %s" % res_city.get("error", "unknown"))
		_cleanup()
		return false

	var city_store := MapStore.new(city_db)
	if not city_store.open_store(false):
		push_error("Failed to open fixture city store: %s" % city_store.last_error)
		_cleanup()
		return false

	if city_store.get_state("schema_version") != "4":
		push_error("Expected city store schema_version '4', got '%s'" % city_store.get_state("schema_version"))
		city_store.close()
		_cleanup()
		return false

	if city_store.get_state("place_id") != "city:fixture-city":
		push_error("Expected place_id 'city:fixture-city', got '%s'" % city_store.get_state("place_id"))
		city_store.close()
		_cleanup()
		return false

	if city_store.get_state("snapshot") != MapConstants.MAP_SNAPSHOT:
		push_error("Expected snapshot '%s', got '%s'" % [MapConstants.MAP_SNAPSHOT, city_store.get_state("snapshot")])
		city_store.close()
		_cleanup()
		return false

	var city_areas := city_store.get_areas()
	var city_areas_map := {}
	for a in city_areas:
		city_areas_map[a["area_key"]] = a

	if not city_areas_map.has("city:fixture-city") or city_areas_map["city:fixture-city"]["cell_count"] != 36:
		push_error("Expected city:fixture-city area with 36 cells, got %s" % str(city_areas_map.get("city:fixture-city")))
		city_store.close()
		_cleanup()
		return false

	var expected_neighbourhoods := {
		"osm:n9103": {"name": "North End", "cell_count": 10},
		"osm:n9104": {"name": "Old Town", "cell_count": 12},
		"osm:n9105": {"name": "Riverside", "cell_count": 10},
		"osm:r9010": {"name": "Mill District", "cell_count": 4}
	}
	for k in expected_neighbourhoods.keys():
		if not city_areas_map.has(k):
			push_error("Missing expected neighbourhood area %s" % k)
			city_store.close()
			_cleanup()
			return false
		var exp_info: Dictionary = expected_neighbourhoods[k]
		if city_areas_map[k]["name"] != exp_info["name"] or city_areas_map[k]["cell_count"] != exp_info["cell_count"]:
			push_error("Area %s mismatch: expected %s, got %s" % [k, str(exp_info), str(city_areas_map[k])])
			city_store.close()
			_cleanup()
			return false

	var city_ac_count: int = int(city_store._rows("SELECT count(*) as c FROM area_cells;")[0]["c"])
	if city_ac_count != 36:
		push_error("Expected 36 area_cells for city, got %d" % city_ac_count)
		city_store.close()
		_cleanup()
		return false

	city_store.close()

	# Site conversion
	var site_db := TEST_DB_PATH + "_site.db"
	_cleanup_path(site_db)
	var conv_site := RegionConverter.new()
	var res_site := conv_site.convert(FIXTURE_PBF, site_db, null, null, "site:fixture-park", FIXTURE_CONFIG)
	if not res_site.get("ok", false):
		push_error("Fixture site conversion failed: %s" % res_site.get("error", "unknown"))
		_cleanup()
		return false

	var site_store := MapStore.new(site_db)
	if not site_store.open_store(false):
		push_error("Failed to open fixture site store: %s" % site_store.last_error)
		_cleanup()
		return false

	var site_areas := site_store.get_areas()
	if site_areas.size() != 1 or site_areas[0]["area_key"] != "site:fixture-park" or site_areas[0]["cell_count"] != 16:
		push_error("Unexpected site areas: %s" % str(site_areas))
		site_store.close()
		_cleanup()
		return false

	var site_ac_count: int = int(site_store._rows("SELECT count(*) as c FROM area_cells WHERE area_key = 'site:fixture-park';")[0]["c"])
	if site_ac_count != 16:
		push_error("Expected 16 area_cells for site, got %d" % site_ac_count)
		site_store.close()
		_cleanup()
		return false

	site_store.close()

	# ---------------------------------------------------------
	# 8. Determinism Test & Coastline Retention Falsifier (§2.5)
	# ---------------------------------------------------------
	var det_a_db := TEST_DB_PATH + "_det_a.db"
	var det_b_db := TEST_DB_PATH + "_det_b.db"
	_cleanup_path(det_a_db)
	_cleanup_path(det_b_db)

	# Clip A matches --place fixed unit (cx in 1..10, cy in 1..10)
	var clip_a := Rect2(256.0, 256.0, 2560.0, 2560.0)
	var conv_a := RegionConverter.new()
	var res_a := conv_a.convert(FIXTURE_PBF, det_a_db, clip_a, [1, 1, 10, 10], "city:fixture-city", FIXTURE_CONFIG)
	if not res_a.get("ok", false):
		push_error("Determinism clip A failed: %s" % res_a.get("error", "unknown"))
		_cleanup()
		return false

	# Clip B is a larger rectangle covering distant coastline (cx in 1..15, cy in 1..10)
	var clip_b := Rect2(256.0, 256.0, 3840.0, 2560.0)
	var conv_b := RegionConverter.new()
	var res_b := conv_b.convert(FIXTURE_PBF, det_b_db, clip_b, [1, 1, 15, 10])
	if not res_b.get("ok", false):
		push_error("Determinism clip B failed: %s" % res_b.get("error", "unknown"))
		_cleanup()
		return false

	var s_place := MapStore.new(city_db)
	s_place.open_store(false)
	var s_a := MapStore.new(det_a_db)
	s_a.open_store(false)
	var s_b := MapStore.new(det_b_db)
	s_b.open_store(false)

	# --place run and Clip A run give identical canonical hashes
	var hash_place := s_place.canonical_dump_sha256()
	var hash_a := s_a.canonical_dump_sha256()
	if hash_place != hash_a:
		push_error("Determinism failed: --place hash %s != Clip A hash %s" % [hash_place, hash_a])
		s_place.close()
		s_a.close()
		s_b.close()
		_cleanup()
		return false

	# Every cell inside the city has byte-identical tile_synth2 buffers between --place and Clip B
	for cy in range(3, 9):
		for cx in range(3, 9):
			var area_p := _build_area(s_place, cx, cy)
			var area_b := _build_area(s_b, cx, cy)
			var synth_p := TileSynth2.synthesize_cell(cx, cy, area_p)
			var synth_b := TileSynth2.synthesize_cell(cx, cy, area_b)
			if synth_p["tiles"] != synth_b["tiles"]:
				push_error("Determinism failed: tile buffer mismatch at city cell (%d, %d)" % [cx, cy])
				s_place.close()
				s_a.close()
				s_b.close()
				_cleanup()
				return false

	# Falsification check (§2.5): before Rule 3, dropping distant coastline outside Clip A changes cell (10, 4) sea flag
	var flag_with_rule3: int = s_a.get_cell_sea(10, 4)
	if flag_with_rule3 != 0:
		push_error("Expected cell (10, 4) sea flag 0 with Rule 3, got %d" % flag_with_rule3)
		s_place.close()
		s_a.close()
		s_b.close()
		_cleanup()
		return false

	s_a._q("DELETE FROM features_line WHERE kind = 'coastline' AND cell_x = 14;")
	s_a._q("DELETE FROM cell_flags;")
	var conv_falsify := RegionConverter.new()
	conv_falsify._compute_and_write_sea_flags(s_a, Rect2i(1, 1, 10, 10))
	var flag_without_rule3: int = s_a.get_cell_sea(10, 4)
	if flag_without_rule3 != 1:
		push_error("Falsifier failed: expected cell (10, 4) sea flag 1 without Rule 3, got %d" % flag_without_rule3)
		s_place.close()
		s_a.close()
		s_b.close()
		_cleanup()
		return false

	s_place.close()
	s_a.close()
	s_b.close()
	_cleanup()
	return true

static func _build_area(store: MapStore, cx: int, cy: int) -> Dictionary:
	var area: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var offset := Vector2i(dx, dy)
			var nx := cx + dx
			var ny := cy + dy
			area[offset] = {
				"polys": store.get_features_poly(nx, ny),
				"lines": store.get_features_line(nx, ny),
				"places": store.get_place_nodes(nx, ny),
				"covered": store.covers_cell(nx, ny),
				"sea": store.get_cell_sea(nx, ny)
			}
	return area

static func _cleanup_path(path: String) -> void:
	for suffix in ["", "-wal", "-shm", ".nodes.tmp", ".coords.tmp", ".rels.tmp"]:
		var p: String = path + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _cleanup() -> void:
	_cleanup_path(TEST_DB_PATH)
	_cleanup_path(TEST_DB_PATH + "_city.db")
	_cleanup_path(TEST_DB_PATH + "_site.db")
	_cleanup_path(TEST_DB_PATH + "_det_a.db")
	_cleanup_path(TEST_DB_PATH + "_det_b.db")
