class_name CaricatureWalkerGrid
extends RefCounted

## game/world/caricature/caricature_walker_grid.gd — Shared Runtime Walkability Oracle (Item 69)
## Shares CaricatureCheck._in_play_bounds, TileSynth2.is_walkable, solid_mask, and TileSynth2.can_jump_ledge
## so runtime walking has 100% parity with CaricatureCheck across all 21 Washington DC maps.
## Contract: docs/implementation_plan_travel_and_time.md §(d)

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")

var _compiled_by_area: Dictionary = {} # area_id -> compiled Dictionary
var _cells_map: Dictionary = {} # Vector2i cell -> {"compiled": Dictionary, "area": Dictionary}
var _reveal_fn: Callable = Callable()
var _opening_masks: Dictionary = {} # area_id -> PackedByteArray
var _street_pokemon_by_area: Dictionary = {} # area_id -> Dictionary(Vector2i local -> Dictionary)
var _doors_by_area: Dictionary = {} # area_id -> Dictionary(Vector2i local -> Dictionary)
var _collected_ball_keys: Dictionary = {} # "ball:<area_id>:<lx>:<ly>" -> true

static func local_to_global(compiled: Dictionary, lx: int, ly: int) -> Vector2i:
	var origin: Vector2i = compiled["origin"]
	var rows: int = int(compiled["rows"])
	return Vector2i(origin.x * 32 + lx, (-(origin.y + rows - 1) - 1) * 32 + ly)

static func global_to_local(compiled: Dictionary, gx: int, gy: int) -> Vector2i:
	var origin: Vector2i = compiled["origin"]
	var rows: int = int(compiled["rows"])
	return Vector2i(gx - origin.x * 32, gy - (-(origin.y + rows - 1) - 1) * 32)

static func global_tile_to_cell(gx: int, gy: int) -> Vector2i:
	return Vector2i(floori(float(gx) / 32.0), -floori(float(gy) / 32.0) - 1)

static func ball_item_key(area_id: String, lx: int, ly: int) -> String:
	return "ball:%s:%d:%d" % [area_id, lx, ly]

func setup(compiled_by_area: Dictionary, cells_map: Dictionary, reveal_fn: Callable = Callable(), collected_keys: Dictionary = {}) -> void:
	_compiled_by_area = compiled_by_area
	_cells_map = cells_map
	_reveal_fn = reveal_fn
	_collected_ball_keys = collected_keys.duplicate()
	_opening_masks.clear()
	_street_pokemon_by_area.clear()
	_doors_by_area.clear()

	for aid_v in _compiled_by_area.keys():
		var aid := str(aid_v)
		var comp: Dictionary = _compiled_by_area[aid_v]
		var w: int = int(comp.get("w", 0))
		var h: int = int(comp.get("h", 0))
		var openings: Array = comp.get("openings", [])
		_opening_masks[aid] = CaricatureCheck._build_opening_mask(w, h, openings)

		var sp_map := {}
		for sp_v in comp.get("street_pokemon", []):
			if sp_v is Dictionary:
				var sp: Dictionary = sp_v
				sp_map[Vector2i(int(sp["x"]), int(sp["y"]))] = sp
		_street_pokemon_by_area[aid] = sp_map

		var door_map := {}
		for d_v in comp.get("doors", []):
			if d_v is Dictionary:
				var d: Dictionary = d_v
				door_map[Vector2i(int(d["x"]), int(d["y"]))] = d
		_doors_by_area[aid] = door_map

func mark_ball_collected(area_id: String, lx: int, ly: int) -> void:
	_collected_ball_keys[ball_item_key(area_id, lx, ly)] = true

func is_ball_collected(area_id: String, lx: int, ly: int) -> bool:
	return _collected_ball_keys.has(ball_item_key(area_id, lx, ly))

func area_at_global(gx: int, gy: int) -> String:
	var cell := global_tile_to_cell(gx, gy)
	if not _cells_map.has(cell):
		return ""
	var entry: Dictionary = _cells_map[cell]
	var a: Dictionary = entry.get("area", {})
	return str(a.get("id", ""))

func is_global_tile_revealed(gx: int, gy: int) -> bool:
	var cell := global_tile_to_cell(gx, gy)
	if not _cells_map.has(cell):
		return false
	if _reveal_fn.is_valid():
		return int(_reveal_fn.call(cell)) > 0
	return true

func is_local_tile_walkable(area_id: String, lx: int, ly: int, treat_hm_as_passable: bool = false) -> bool:
	if not _compiled_by_area.has(area_id):
		return false
	var comp: Dictionary = _compiled_by_area[area_id]
	var w: int = int(comp.get("w", 0))
	var h: int = int(comp.get("h", 0))
	var opening_mask: PackedByteArray = _opening_masks.get(area_id, PackedByteArray())
	if not CaricatureCheck._in_play_bounds(lx, ly, w, h, opening_mask):
		return false
	var idx := ly * w + lx
	var solid_mask: PackedByteArray = comp.get("solid_mask", PackedByteArray())
	if solid_mask.size() == w * h and solid_mask[idx] == 1:
		return false
	var sp_map: Dictionary = _street_pokemon_by_area.get(area_id, {})
	if sp_map.has(Vector2i(lx, ly)):
		return false
	var cls_buf: PackedByteArray = comp["class"]
	var var_buf: PackedByteArray = comp["variant"]
	var mask_buf: PackedByteArray = comp["mask"]
	var cls: int = cls_buf[idx]
	if cls == TileSynth2.TILE_ITEM_BALL:
		return is_ball_collected(area_id, lx, ly)
	if treat_hm_as_passable and TileSynth2.is_field_clearable(cls):
		return true
	return TileSynth2.is_walkable(cls, var_buf[idx], mask_buf[idx])

func evaluate_step(from_gx: int, from_gy: int, dir: Vector2i) -> Dictionary:
	if dir == Vector2i.ZERO:
		return {"action": "blocked", "reason": "none", "tile": Vector2i(from_gx, from_gy), "area_id": area_at_global(from_gx, from_gy)}

	var from_aid := area_at_global(from_gx, from_gy)
	var tx := from_gx + dir.x
	var ty := from_gy + dir.y
	var to_cell := global_tile_to_cell(tx, ty)

	# 1. Revealed / fog check
	if not _cells_map.has(to_cell):
		return {"action": "blocked", "reason": "fog", "tile": Vector2i(tx, ty), "area_id": ""}
	if _reveal_fn.is_valid() and int(_reveal_fn.call(to_cell)) <= 0:
		var locked_area := area_at_global(tx, ty)
		return {"action": "blocked", "reason": "fog", "tile": Vector2i(tx, ty), "area_id": locked_area}

	var to_aid := area_at_global(tx, ty)
	if to_aid.is_empty() or not _compiled_by_area.has(to_aid):
		return {"action": "blocked", "reason": "fog", "tile": Vector2i(tx, ty), "area_id": ""}

	var comp: Dictionary = _compiled_by_area[to_aid]
	var w: int = int(comp["w"])
	var h: int = int(comp["h"])
	var opening_mask: PackedByteArray = _opening_masks.get(to_aid, PackedByteArray())
	var local_t := global_to_local(comp, tx, ty)
	var lx := local_t.x
	var ly := local_t.y

	if not CaricatureCheck._in_play_bounds(lx, ly, w, h, opening_mask):
		return {"action": "blocked", "reason": "wall", "tile": Vector2i(tx, ty), "area_id": to_aid}

	var idx := ly * w + lx
	var cls_buf: PackedByteArray = comp["class"]
	var var_buf: PackedByteArray = comp["variant"]
	var mask_buf: PackedByteArray = comp["mask"]
	var cls: int = cls_buf[idx]

	# 2. Door entry check when stepping North onto a TILE_DOOR
	if cls == TileSynth2.TILE_DOOR:
		var door_map: Dictionary = _doors_by_area.get(to_aid, {})
		var d_entry: Dictionary = door_map.get(Vector2i(lx, ly), {})
		var iid := str(d_entry.get("interior", ""))
		if dir == Vector2i(0, -1) and not iid.is_empty():
			return {
				"action": "door",
				"door": d_entry,
				"door_tile": Vector2i(tx, ty),
				"door_local": Vector2i(lx, ly),
				"area_id": to_aid,
			}
		return {"action": "blocked", "reason": "door_locked", "tile": Vector2i(tx, ty), "area_id": to_aid}

	# 3. Ledge one-way 2-tile hop check
	if cls == TileSynth2.TILE_LEDGE:
		var land_gx := from_gx + dir.x * 2
		var land_gy := from_gy + dir.y * 2
		var land_aid := area_at_global(land_gx, land_gy)
		if land_aid == to_aid and is_global_tile_revealed(land_gx, land_gy):
			var land_l := global_to_local(comp, land_gx, land_gy)
			if is_local_tile_walkable(to_aid, land_l.x, land_l.y):
				var land_idx := land_l.y * w + land_l.x
				var land_cls: int = cls_buf[land_idx]
				var land_mask: int = mask_buf[land_idx]
				if land_cls == TileSynth2.TILE_ITEM_BALL and is_ball_collected(to_aid, land_l.x, land_l.y):
					land_cls = TileSynth2.TILE_GRASS
					land_mask = 0
				if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, var_buf[idx], land_cls, land_mask, dir):
					return {
						"action": "ledge",
						"over": Vector2i(tx, ty),
						"to": Vector2i(land_gx, land_gy),
						"from_area": from_aid,
						"to_area": land_aid,
						"crossed_seam": (from_aid != land_aid),
						"landing_class": cls_buf[land_idx],
					}
		return {"action": "blocked", "reason": "ledge_wrong_dir", "tile": Vector2i(tx, ty), "area_id": to_aid}

	# 4. Standard walkability check
	if is_local_tile_walkable(to_aid, lx, ly):
		return {
			"action": "step",
			"to": Vector2i(tx, ty),
			"from_area": from_aid,
			"to_area": to_aid,
			"crossed_seam": (from_aid != to_aid),
		}

	# 5. Classify exact block reason for interact / bump feedback
	var reason := "wall"
	var solid_mask: PackedByteArray = comp.get("solid_mask", PackedByteArray())
	var sp_map: Dictionary = _street_pokemon_by_area.get(to_aid, {})
	if (solid_mask.size() == w * h and solid_mask[idx] == 1) or sp_map.has(Vector2i(lx, ly)):
		reason = "entity"
	elif cls == TileSynth2.TILE_WATER:
		reason = "water"
	elif cls == TileSynth2.TILE_CLIFF:
		reason = "cliff"
	elif cls == TileSynth2.TILE_CUT_TREE:
		reason = "cut"
	elif cls == TileSynth2.TILE_SMASH_ROCK:
		reason = "rock_smash"
	elif cls == TileSynth2.TILE_BOULDER:
		reason = "boulder"
	elif cls == TileSynth2.TILE_ITEM_BALL:
		reason = "item_ball"
	elif cls == TileSynth2.TILE_SIGN:
		reason = "sign"
	return {"action": "blocked", "reason": reason, "tile": Vector2i(tx, ty), "area_id": to_aid}
