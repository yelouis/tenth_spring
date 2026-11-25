class_name InteriorView
extends Node2D

## game/world/interior/interior_view.gd — Playable DC Interior Room Renderer & Screenshot Capture (Item 57)
## Layer order (plan §11.3 D):
##   void backdrop -> indoor 0..16 base tiles (32 px/tile, Emerald hybrid or CC0/procedural fallback)
##   -> flat floor props (int_warp_pad, int_wind_grate) + flyer floor shadow
##   -> y-sorted upright stamps (110..134 scaled 2x nearest) & NPC sprites
##   -> ceiling-hung props (int_suspended_flyer) -> haunted tint -> HUD label.

const InteriorTiles := preload("res://world/interior/interior_tiles.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorCheck := preload("res://world/interior/interior_check.gd")
const AssetDB := preload("res://rom/asset_db.gd")
const PeopleSprites := preload("res://world/people_sprites.gd")
const PlayerWalker := preload("res://world/player_walker.gd")
const WorldClock := preload("res://world/world_clock.gd")

const TILE_PX: int = 32
const STAMP_SCALE: float = 2.0
const WALK_ZOOM_STEPS: Array = [0.5, 1.0, 2.0]

signal exit_requested(return_info: Dictionary)
signal floor_changed(new_floor_index: int, spawn_tile: Vector2i)
signal session_changed(interior_id: String, floor_index: int, tile: Vector2i, facing: String)
signal switch_toggled(switch_id: String, opened_gates: Array)

static var _shared_stamp_tex_cache: Dictionary = {}

var screenshot_timeout_sec: float = 120.0

var _compiled: Dictionary = {}
var _floor_index: int = 0
var _atlas_source_kind: String = "fallback"
var _cache_dir: String = AssetDB.DEFAULT_CACHE_DIR
var _force_fallback: bool = false
var _stamp_tex_cache: Dictionary = {}
var _npc_tex_cache: Dictionary = {}
var _atlas_slice_cache: Dictionary = {}

var _walk_mode: bool = false
var _player_walker: PlayerWalker = null
var _world_clock: WorldClock = null
var _db_override = null
var _return_info: Dictionary = {}
var _zoom_step: float = 2.0
var _open_gates: Dictionary = {} # gate_id -> true (session-scoped)
var _gate_sprites: Dictionary = {} # gate_id -> Array[Sprite2D]
var _collected_item_keys: Dictionary = {} # item_key -> true
var _item_sprites_by_pos: Dictionary = {} # Vector2i -> Sprite2D
var _item_defs_by_pos: Dictionary = {} # Vector2i -> Dictionary
var _npc_entries_by_pos: Dictionary = {} # Vector2i -> Dictionary {"sprite": Sprite2D, "npc": Dictionary}
var _block_mask: PackedByteArray = PackedByteArray()
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_timer: float = 0.0
var _last_toast_text: String = ""
var _dialogue_box: Control = null

var _backdrop: ColorRect = null
var _tile_layer: TileMapLayer = null
var _overlay_tile_layer: TileMapLayer = null
var _floor_dais_layer: Node2D = null
var _floor_flat_layer: Node2D = null
var _ysort_layer: Node2D = null
var _ceiling_layer: Node2D = null
var _camera: Camera2D = null
var _hud_canvas: CanvasLayer = null
var _tint_rect: ColorRect = null
var _banner: PanelContainer = null
var _title_label: Label = null

var _screenshot_active: bool = false
var _screenshot_path: String = ""
var _screenshot_frames_left: int = 0
var _screenshot_elapsed_sec: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func get_atlas_source_kind() -> String:
	return _atlas_source_kind

func get_floor_index() -> int:
	return _floor_index

func get_player_walker() -> PlayerWalker:
	return _player_walker

func get_last_toast_text() -> String:
	return _last_toast_text

func get_world_clock() -> WorldClock:
	return _world_clock

func set_walk_zoom(zoom_val: float) -> void:
	_zoom_step = zoom_val
	if _camera != null:
		_camera.zoom = Vector2(_zoom_step, _zoom_step)
		if _player_walker != null:
			_camera.position = _player_walker.get_camera_target()

func _get_db():
	if _db_override != null:
		return _db_override
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.has_node("DB"):
		return tree.root.get_node("DB")
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _walk_mode and not _screenshot_active:
			if _world_clock != null:
				_world_clock.save_to_db()
			persist_indoor_session()

static func indoor_item_key(interior_id: String, floor_id: String, item_dict: Dictionary) -> String:
	var iid := str(item_dict.get("id", ""))
	if not iid.is_empty():
		return "indoor:%s:%s" % [interior_id, iid]
	var at_v: Variant = InteriorMap._parse_vec2i(item_dict.get("at", null))
	if at_v is Vector2i:
		var p: Vector2i = at_v
		return "indoor:%s:%s:%d:%d" % [interior_id, floor_id, p.x, p.y]
	return ""

func get_floor_size() -> Vector2i:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index >= 0 and _floor_index < floors.size():
		var fd: Dictionary = floors[_floor_index]
		return Vector2i(int(fd.get("w", 0)), int(fd.get("h", 0)))
	return Vector2i.ZERO

func extract_rendered_stamp_image_32(sid: int) -> Image:
	for layer in [_ysort_layer, _floor_flat_layer, _ceiling_layer]:
		if layer == null:
			continue
		for ch in layer.get_children():
			if ch is Sprite2D and ch.has_meta("stamp_id") and int(ch.get_meta("stamp_id")) == sid:
				var sp := ch as Sprite2D
				var tex := sp.texture
				if tex == null:
					return null
				var img: Image
				if tex is AtlasTexture:
					var atex := tex as AtlasTexture
					if atex.atlas == null:
						return null
					var full_img := atex.atlas.get_image()
					if full_img == null:
						return null
					full_img.convert(Image.FORMAT_RGBA8)
					img = full_img.get_region(Rect2i(
						int(round(atex.region.position.x)),
						int(round(atex.region.position.y)),
						int(round(atex.region.size.x)),
						int(round(atex.region.size.y))
					))
				else:
					img = tex.get_image()
					if img == null:
						return null
					img = img.duplicate() as Image
					img.convert(Image.FORMAT_RGBA8)
				var sx := int(round(sp.scale.x))
				var sy := int(round(sp.scale.y))
				if sx > 1 or sy > 1:
					img.resize(img.get_width() * maxi(1, sx), img.get_height() * maxi(1, sy), Image.INTERPOLATE_NEAREST)
				return img
	return null

func _get_tile_atlas_image() -> Image:
	if _tile_layer == null or _tile_layer.tile_set == null:
		return null
	var src := _tile_layer.tile_set.get_source(0) as TileSetAtlasSource
	if src == null or src.texture == null:
		return null
	var img := src.texture.get_image()
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
	return img

static func _blend_tile_cell_px(dst: Color, layer: TileMapLayer, atlas_img: Image, cell: Vector2i, local: Vector2i) -> Color:
	if layer == null or atlas_img == null or layer.get_cell_source_id(cell) == -1:
		return dst
	var ac := layer.get_cell_atlas_coords(cell)
	var ax := ac.x * TILE_PX + local.x
	var ay := ac.y * TILE_PX + local.y
	if ax < 0 or ay < 0 or ax >= atlas_img.get_width() or ay >= atlas_img.get_height():
		return dst
	var src := atlas_img.get_pixel(ax, ay)
	if src.a <= 0.0:
		return dst
	return Color(
		src.r * src.a + dst.r * (1.0 - src.a),
		src.g * src.a + dst.g * (1.0 - src.a),
		src.b * src.a + dst.b * (1.0 - src.a),
		1.0
	)

static func _composite_tint_rect(dst: Color, cr: ColorRect) -> Color:
	var c := cr.color
	if cr.material is CanvasItemMaterial and (cr.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_MUL:
		var mul := Color(dst.r * c.r, dst.g * c.g, dst.b * c.b, 1.0)
		return dst.lerp(mul, c.a)
	return Color(
		c.r * c.a + dst.r * (1.0 - c.a),
		c.g * c.a + dst.g * (1.0 - c.a),
		c.b * c.a + dst.b * (1.0 - c.a),
		1.0
	)

static func _to_color8_opaque(c: Color) -> Color:
	return Color8(
		int(round(clampf(c.r, 0.0, 1.0) * 255.0)),
		int(round(clampf(c.g, 0.0, 1.0) * 255.0)),
		int(round(clampf(c.b, 0.0, 1.0) * 255.0)),
		255
	)

func _sample_base_world_px(world_px: Vector2, atlas_img: Image) -> Color:
	var dst := _backdrop.color if (_backdrop != null and Rect2(_backdrop.position, _backdrop.size).has_point(world_px)) else Color(0, 0, 0, 1)
	if world_px.x >= 0.0 and world_px.y >= 0.0:
		var cell := Vector2i(int(floor(world_px.x / float(TILE_PX))), int(floor(world_px.y / float(TILE_PX))))
		var local := Vector2i(int(floor(world_px.x)) - cell.x * TILE_PX, int(floor(world_px.y)) - cell.y * TILE_PX)
		dst = _blend_tile_cell_px(dst, _tile_layer, atlas_img, cell, local)
		dst = _blend_tile_cell_px(dst, _overlay_tile_layer, atlas_img, cell, local)
	return dst

func get_untinted_base_pixel_at_world(world_px: Vector2) -> Color:
	return _to_color8_opaque(_sample_base_world_px(world_px, _get_tile_atlas_image()))

func _sample_world_px_with_atlas(world_px: Vector2, atlas_img: Image) -> Color:
	var dst := _sample_base_world_px(world_px, atlas_img)
	for ch in get_children():
		if ch is ColorRect and ch != _backdrop and ch.visible and ch.z_index > 0:
			var cr := ch as ColorRect
			if Rect2(cr.position, cr.size).has_point(world_px):
				dst = _composite_tint_rect(dst, cr)
	if _hud_canvas != null:
		for hch in _hud_canvas.get_children():
			if hch is ColorRect and hch.visible:
				var hcr := hch as ColorRect
				var full_anchors := is_zero_approx(hcr.anchor_left) and is_zero_approx(hcr.anchor_top) and is_equal_approx(hcr.anchor_right, 1.0) and is_equal_approx(hcr.anchor_bottom, 1.0)
				if full_anchors:
					dst = _composite_tint_rect(dst, hcr)
	return _to_color8_opaque(dst)

func sample_rendered_pixel_at_world(world_px: Vector2) -> Color:
	return _sample_world_px_with_atlas(world_px, _get_tile_atlas_image())

func render_view_cell_32(cell: Vector2i) -> Image:
	var atlas_img := _get_tile_atlas_image()
	var out := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	var ox := float(cell.x * TILE_PX)
	var oy := float(cell.y * TILE_PX)
	for py in range(TILE_PX):
		for px in range(TILE_PX):
			out.set_pixel(px, py, _sample_world_px_with_atlas(Vector2(ox + float(px) + 0.5, oy + float(py) + 0.5), atlas_img))
	return out

func load_interior(interior_key: String, floor_index: int = 0, cache_dir: String = AssetDB.DEFAULT_CACHE_DIR, force_fallback: bool = false) -> bool:
	var path := InteriorMap.resolve_interior_path(interior_key)
	if path.is_empty():
		push_error("InteriorView: unknown interior '%s'" % interior_key)
		return false
	var doc := InteriorMap.load_json(path)
	if doc.is_empty():
		push_error("InteriorView: failed to parse interior JSON at %s" % path)
		return false
	return load_from_dict(doc, floor_index, cache_dir, force_fallback)

func load_from_dict(doc: Dictionary, floor_index: int = 0, cache_dir: String = AssetDB.DEFAULT_CACHE_DIR, force_fallback: bool = false) -> bool:
	var comp := InteriorMap.compile(doc)
	var floors: Array = comp.get("floors", [])
	if not bool(comp.get("ok", false)) or floor_index < 0 or floor_index >= floors.size():
		push_error("InteriorView: invalid floor index %d for interior '%s'" % [floor_index, str(doc.get("id", ""))])
		return false
	_compiled = comp
	_floor_index = floor_index
	_cache_dir = cache_dir
	_force_fallback = force_fallback
	_rebuild_scene(cache_dir, force_fallback)
	return true

func _clear_scene() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.free()
	_backdrop = null
	_tile_layer = null
	_overlay_tile_layer = null
	_floor_dais_layer = null
	_floor_flat_layer = null
	_ysort_layer = null
	_ceiling_layer = null
	_camera = null
	_hud_canvas = null
	_tint_rect = null
	_banner = null
	_title_label = null
	_toast_panel = null
	_toast_label = null
	_dialogue_box = null
	_player_walker = null
	_gate_sprites.clear()
	_item_sprites_by_pos.clear()
	_item_defs_by_pos.clear()
	_npc_entries_by_pos.clear()
	_atlas_slice_cache.clear()

func _load_stamp_texture(rel_path: String) -> Texture2D:
	if _shared_stamp_tex_cache.has(rel_path):
		return _shared_stamp_tex_cache[rel_path]
	if _stamp_tex_cache.has(rel_path):
		return _stamp_tex_cache[rel_path]
	var abs_p := ProjectSettings.globalize_path("res://assets/original/" + rel_path)
	var bytes := FileAccess.get_file_as_bytes(abs_p)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_shared_stamp_tex_cache[rel_path] = tex
	_stamp_tex_cache[rel_path] = tex
	return tex

func _get_npc_texture(role: String, sprite_key: String = "", facing: String = "S", force_fallback: bool = false, cache_dir: String = AssetDB.DEFAULT_CACHE_DIR) -> Texture2D:
	return PeopleSprites.resolve_texture(sprite_key, facing, role, force_fallback, cache_dir)

func _build_tileset(strip_tex: Texture2D, cols: int = InteriorTiles.CLASS_COUNT, rows: int = 1) -> TileSet:
	return InteriorTiles.resolve_tileset(strip_tex, cols, rows)

func _get_atlas_cell_tex(strip_tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var key := "%d:%d" % [col, row]
	if _atlas_slice_cache.has(key):
		return _atlas_slice_cache[key] as AtlasTexture
	var atex := AtlasTexture.new()
	atex.atlas = strip_tex
	atex.region = Rect2(float(col * TILE_PX), float(row * TILE_PX), float(TILE_PX), float(TILE_PX))
	_atlas_slice_cache[key] = atex
	return atex

func _rebuild_scene(cache_dir: String, force_fallback: bool) -> void:
	_clear_scene()
	var floors: Array = _compiled.get("floors", [])
	var fd: Dictionary = floors[_floor_index]
	var w := int(fd["w"])
	var h := int(fd["h"])
	var world_w := float(w * TILE_PX)
	var world_h := float(h * TILE_PX)

	# 1. Pure black void backdrop around room (#000000)
	_backdrop = ColorRect.new()
	_backdrop.name = "VoidBackdrop"
	_backdrop.color = Color8(0, 0, 0, 255)
	_backdrop.position = Vector2(-2048.0, -2048.0)
	_backdrop.size = Vector2(world_w + 4096.0, world_h + 4096.0)
	_backdrop.z_index = -10
	add_child(_backdrop)

	# 2. Indoor base TileMapLayer + Layer-1 kit overlay (rugs)
	var bundle := InteriorTiles.resolve_atlas_bundle(cache_dir, force_fallback)
	var strip_tex: Texture2D = bundle["texture"]
	_atlas_source_kind = str(bundle["source"])
	var atlas_cols := int(bundle.get("cols", InteriorTiles.CLASS_COUNT))
	var atlas_rows := int(bundle.get("rows", 1))
	var ts := _build_tileset(strip_tex, atlas_cols, atlas_rows)

	var kit_id := str(fd.get("kit", ""))
	var kits_dict: Dictionary = bundle.get("kits", {})
	var kit_def: Dictionary = kits_dict.get(kit_id, {}) if (not kit_id.is_empty() and kits_dict.has(kit_id)) else {}
	var kit_cells := InteriorTiles.resolve_kit_cells(fd, kit_def)

	_tile_layer = TileMapLayer.new()
	_tile_layer.name = "IndoorTileLayer"
	_tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tile_layer.tile_set = ts
	_tile_layer.z_index = 0
	for b_cell in (kit_cells["base"] as Array):
		var bc := b_cell as Dictionary
		_tile_layer.set_cell(bc["pos"] as Vector2i, 0, bc["atlas"] as Vector2i)
	add_child(_tile_layer)

	_overlay_tile_layer = TileMapLayer.new()
	_overlay_tile_layer.name = "IndoorOverlayTileLayer"
	_overlay_tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay_tile_layer.tile_set = ts
	_overlay_tile_layer.z_index = 1
	for o_cell in (kit_cells["overlay"] as Array):
		var oc := o_cell as Dictionary
		_overlay_tile_layer.set_cell(oc["pos"] as Vector2i, 0, oc["atlas"] as Vector2i)
	add_child(_overlay_tile_layer)

	# 3. Dais underlay, Flat floor/wall layer, Y-sorted upright layer, and Ceiling layer
	_floor_dais_layer = Node2D.new()
	_floor_dais_layer.name = "FloorDaisLayer"
	_floor_dais_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_dais_layer.z_index = 1
	add_child(_floor_dais_layer)

	_floor_flat_layer = Node2D.new()
	_floor_flat_layer.name = "FloorFlatLayer"
	_floor_flat_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_flat_layer.z_index = 2
	add_child(_floor_flat_layer)

	_ysort_layer = Node2D.new()
	_ysort_layer.name = "YSortPropsLayer"
	_ysort_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ysort_layer.y_sort_enabled = true
	_ysort_layer.z_index = 3
	add_child(_ysort_layer)

	_ceiling_layer = Node2D.new()
	_ceiling_layer.name = "CeilingHangLayer"
	_ceiling_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ceiling_layer.z_index = 5
	add_child(_ceiling_layer)

	# 3a. Emerald runtime small furniture & wall fixtures
	var fx_atlas_map: Dictionary = bundle.get("fixtures", {})
	for fx_v in (fd.get("fixtures", []) as Array):
		var fx: Dictionary = fx_v
		var fx_id := str(fx.get("fixture", ""))
		if not fx_atlas_map.has(fx_id):
			continue
		var fx_meta := fx_atlas_map[fx_id] as Dictionary
		var fx_cells: Array = fx_meta.get("cells", [])
		var at: Vector2i = fx["at"]
		var fh := int(fx.get("h", fx_cells.size()))
		var fbase := int(fx.get("base_rows", 1))
		var funderlay := bool(fx_meta.get("underlay", false))
		if funderlay or fbase <= 0:
			var flat_target: Node2D = _floor_dais_layer if funderlay else _floor_flat_layer
			for cy in range(fx_cells.size()):
				var row_arr: Array = fx_cells[cy]
				for cx in range(row_arr.size()):
					var coords: Array = row_arr[cx]
					var fsp := Sprite2D.new()
					fsp.texture = _get_atlas_cell_tex(strip_tex, int(coords[0]), int(coords[1]))
					fsp.centered = false
					fsp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					fsp.position = Vector2(float((at.x + cx) * TILE_PX), float((at.y + cy) * TILE_PX))
					flat_target.add_child(fsp)
		else:
			var holder := Node2D.new()
			holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			holder.position = Vector2(float(at.x * TILE_PX), float((at.y + fh) * TILE_PX))
			for cy in range(fx_cells.size()):
				var row_arr: Array = fx_cells[cy]
				for cx in range(row_arr.size()):
					var coords: Array = row_arr[cx]
					var fsp := Sprite2D.new()
					fsp.texture = _get_atlas_cell_tex(strip_tex, int(coords[0]), int(coords[1]))
					fsp.centered = false
					fsp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					fsp.position = Vector2(float(cx * TILE_PX), float((cy - fh) * TILE_PX))
					holder.add_child(fsp)
			_ysort_layer.add_child(holder)

	var interior_id := str(_compiled.get("id", ""))
	var floor_id := str(fd.get("floor_id", str(_floor_index)))
	for it_v in (fd.get("items", []) as Array):
		if it_v is Dictionary:
			var it_d: Dictionary = it_v
			var it_at: Variant = InteriorMap._parse_vec2i(it_d.get("at", null))
			if it_at is Vector2i:
				_item_defs_by_pos[it_at as Vector2i] = it_d

	var stamp_overrides: Dictionary = bundle.get("stamp_overrides", {})
	for st_v in (fd["stamps"] as Array):
		var st: Dictionary = st_v
		var sid := int(st["stamp_id"])
		var sid_str := str(sid)
		var at: Vector2i = st["at"]
		var sw := int(st["w"])
		var sh := int(st["h"])
		var sbase := int(st["base_rows"])
		var gate_id := str(st.get("gate_id", ""))

		var sp := Sprite2D.new()
		sp.set_meta("stamp_id", sid)
		sp.centered = false
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var use_rom_obj := false
		if stamp_overrides.has(sid_str):
			var ov_coords: Array = stamp_overrides[sid_str] as Array
			if ov_coords.size() >= 2:
				sp.texture = _get_atlas_cell_tex(strip_tex, int(ov_coords[0]), int(ov_coords[1]))
				sp.scale = Vector2(1.0, 1.0)
				sp.set_meta("stamp_source", "rom_object")
				use_rom_obj = true
		if not use_rom_obj:
			var rel_p := str(st["path"])
			var tex := _load_stamp_texture(rel_p)
			if tex == null:
				sp.free()
				continue
			sp.texture = tex
			sp.scale = Vector2(STAMP_SCALE, STAMP_SCALE)
			sp.set_meta("stamp_source", "fallback_stamp")

		if not gate_id.is_empty():
			if not _gate_sprites.has(gate_id):
				_gate_sprites[gate_id] = []
			(_gate_sprites[gate_id] as Array).append(sp)
			if _open_gates.has(gate_id):
				sp.visible = false
		if str(st.get("id", "")) == "int_item_ball" or sid == 110:
			_item_sprites_by_pos[at] = sp
			if _item_defs_by_pos.has(at):
				var ikey := indoor_item_key(interior_id, floor_id, _item_defs_by_pos[at] as Dictionary)
				if not ikey.is_empty() and _collected_item_keys.has(ikey):
					sp.visible = false

		if sid == 120:
			# Ceiling-hung suspended flyer: draw subtle shadow on floor below + sprite overhead
			var shadow := ColorRect.new()
			shadow.color = Color(0.05, 0.06, 0.10, 0.22)
			shadow.position = Vector2(float(at.x * TILE_PX + 24), float((at.y + sh) * TILE_PX - 12))
			shadow.size = Vector2(float(sw * TILE_PX - 48), 16.0)
			_floor_flat_layer.add_child(shadow)
			sp.position = Vector2(float(at.x * TILE_PX), float(at.y * TILE_PX))
			_ceiling_layer.add_child(sp)
		elif sbase <= 0:
			# Flat floor/wall prop (int_warp_pad, int_wind_grate, int_speech_tablet, etc.)
			sp.position = Vector2(float(at.x * TILE_PX), float(at.y * TILE_PX))
			_floor_flat_layer.add_child(sp)
		else:
			# Upright Y-sorted prop sorted by bottom edge
			sp.position = Vector2(float(at.x * TILE_PX), float((at.y + sh) * TILE_PX))
			sp.offset = Vector2(0.0, float(-sh * TILE_PX if use_rom_obj else -sh * 16))
			_ysort_layer.add_child(sp)

	# 4. NPC sprites in Y-sort layer (shared Emerald 16x32 -> 32x64 sprites + fallback)
	for npc_v in (fd["npcs"] as Array):
		var npc: Dictionary = npc_v
		var np_at: Variant = InteriorMap._parse_vec2i(npc.get("at", null))
		if np_at is Vector2i:
			var np_pos: Vector2i = np_at
			var ntex := _get_npc_texture(
				str(npc.get("role", "talk")),
				str(npc.get("sprite", "")),
				str(npc.get("facing", "S")),
				force_fallback,
				cache_dir
			)
			var nsp := Sprite2D.new()
			nsp.texture = ntex
			nsp.centered = false
			nsp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			nsp.scale = Vector2(1.0, 1.0)
			nsp.position = Vector2(float(np_pos.x * TILE_PX), float((np_pos.y + 1) * TILE_PX))
			nsp.offset = Vector2(0.0, -64.0)
			_ysort_layer.add_child(nsp)
			_npc_entries_by_pos[np_pos] = {"sprite": nsp, "npc": npc}

	# 5. Camera centered on floor
	_camera = Camera2D.new()
	_camera.name = "InteriorCamera"
	_camera.position = Vector2(world_w * 0.5, world_h * 0.5)
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()

	# 6. Haunted lighting tint & compact HUD header
	_hud_canvas = CanvasLayer.new()
	_hud_canvas.layer = 10
	add_child(_hud_canvas)

	if str(_compiled.get("atmosphere", "normal")) == "haunted":
		_tint_rect = ColorRect.new()
		_tint_rect.name = "HauntedTint"
		_tint_rect.color = Color(0.84, 0.80, 0.95, 1.0)
		var mul_mat := CanvasItemMaterial.new()
		mul_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		_tint_rect.material = mul_mat
		_tint_rect.position = Vector2.ZERO
		_tint_rect.size = Vector2(world_w, world_h)
		_tint_rect.z_index = 6
		_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tint_rect)

	_banner = PanelContainer.new()
	_banner.position = Vector2(12.0, 10.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.84)
	sb.border_color = Color(0.42, 0.48, 0.60, 0.90)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	_banner.add_theme_stylebox_override("panel", sb)

	_title_label = Label.new()
	_title_label.text = "%s  —  %s" % [str(_compiled.get("title", "")), str(fd.get("label", ""))]
	_title_label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.98, 1.0))
	_title_label.add_theme_font_size_override("font_size", 14)
	_banner.add_child(_title_label)
	_hud_canvas.add_child(_banner)

	_toast_panel = PanelContainer.new()
	_toast_panel.name = "InteriorToastPanel"
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = -260.0
	_toast_panel.offset_right = 260.0
	_toast_panel.offset_top = -58.0
	_toast_panel.offset_bottom = -22.0
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.09, 0.11, 0.17, 0.92)
	tsb.border_color = Color(0.82, 0.68, 0.36, 0.85)
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(5)
	tsb.content_margin_left = 12.0
	tsb.content_margin_right = 12.0
	tsb.content_margin_top = 5.0
	tsb.content_margin_bottom = 5.0
	_toast_panel.add_theme_stylebox_override("panel", tsb)
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82, 1.0))
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false
	_hud_canvas.add_child(_toast_panel)

func show_toast(msg: String, duration: float = 3.5) -> void:
	_last_toast_text = msg
	_toast_timer = maxf(0.5, duration)
	if _toast_label != null:
		_toast_label.text = msg
	if _toast_panel != null:
		_toast_panel.visible = not msg.is_empty()

func _load_collected_indoor_items() -> void:
	_collected_item_keys.clear()
	var db = _get_db()
	var interior_id := str(_compiled.get("id", ""))
	if db != null and db.is_open() and db.has_method("get_collected_items_in_area") and not interior_id.is_empty():
		for row_v in db.get_collected_items_in_area(interior_id):
			if row_v is Dictionary:
				_collected_item_keys[str((row_v as Dictionary).get("item_key", ""))] = true

func _rebuild_block_mask() -> void:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size():
		_block_mask = PackedByteArray()
		return
	var fd: Dictionary = floors[_floor_index]
	var w := int(fd["w"])
	var h := int(fd["h"])
	_block_mask = InteriorCheck._build_block_mask(fd, _open_gates, false, true)
	# Collected indoor items clear their int_item_ball stamp tile in _block_mask
	var interior_id := str(_compiled.get("id", ""))
	var floor_id := str(fd.get("floor_id", str(_floor_index)))
	for pos_v in _item_defs_by_pos.keys():
		var pos: Vector2i = pos_v
		var ikey := indoor_item_key(interior_id, floor_id, _item_defs_by_pos[pos] as Dictionary)
		if pos.x >= 0 and pos.x < w and pos.y >= 0 and pos.y < h:
			if not ikey.is_empty() and _collected_item_keys.has(ikey):
				_block_mask[pos.y * w + pos.x] = 0
				if _item_sprites_by_pos.has(pos) and is_instance_valid(_item_sprites_by_pos[pos]):
					(_item_sprites_by_pos[pos] as Sprite2D).visible = false
			else:
				_block_mask[pos.y * w + pos.x] = 1
	for npc_pos_v in _npc_entries_by_pos.keys():
		var npos: Vector2i = npc_pos_v
		if npos.x >= 0 and npos.x < w and npos.y >= 0 and npos.y < h:
			_block_mask[npos.y * w + npos.x] = 1

func is_tile_passable_for_walker(x: int, y: int) -> bool:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size():
		return false
	return InteriorCheck._is_tile_passable(floors[_floor_index] as Dictionary, _block_mask, x, y)

func mark_indoor_item_collected(pos: Vector2i) -> void:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size() or not _item_defs_by_pos.has(pos):
		return
	var fd: Dictionary = floors[_floor_index]
	var interior_id := str(_compiled.get("id", ""))
	var floor_id := str(fd.get("floor_id", str(_floor_index)))
	var it_d: Dictionary = _item_defs_by_pos[pos]
	var ikey := indoor_item_key(interior_id, floor_id, it_d)
	if ikey.is_empty():
		return
	_collected_item_keys[ikey] = true
	var db = _get_db()
	if db != null and db.is_open() and db.has_method("mark_item_collected"):
		db.mark_item_collected(ikey, interior_id, "indoor", str(it_d.get("name", "Item")))
	if _item_sprites_by_pos.has(pos) and is_instance_valid(_item_sprites_by_pos[pos]):
		(_item_sprites_by_pos[pos] as Sprite2D).visible = false
	_rebuild_block_mask()

func enable_walking(spawn_tile: Vector2i = Vector2i(-1, -1), facing_str: String = "N", return_info: Dictionary = {}, clock_override = null, db_override = null) -> bool:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size():
		return false
	_db_override = db_override
	_return_info = return_info.duplicate(true)
	_walk_mode = true
	_zoom_step = 2.0 # Emerald 15x10 screen at 960x640 (Decision 79 / F81)

	var db = _get_db()
	if clock_override != null:
		_world_clock = clock_override
		_world_clock.set_running(true)
	else:
		_world_clock = WorldClock.new()
		_world_clock.load_from_db(db)
		_world_clock.set_running(true)

	_load_collected_indoor_items()
	_rebuild_block_mask()

	var fd: Dictionary = floors[_floor_index]
	var target_pos := spawn_tile
	if target_pos.x < 0 or target_pos.y < 0:
		var dms: Array = fd.get("door_mats", [])
		if not dms.is_empty():
			target_pos = dms[0] as Vector2i
		else:
			target_pos = Vector2i(int(fd["w"]) / 2, int(fd["h"]) - 2)

	_spawn_or_place_walker(target_pos, facing_str)
	if _camera != null:
		_camera.zoom = Vector2(_zoom_step, _zoom_step)
		_camera.position = _player_walker.get_camera_target()
		_camera.make_current()
	set_process(true)
	persist_indoor_session()
	return true

func _spawn_or_place_walker(tile: Vector2i, facing_str: String) -> void:
	if _player_walker == null or not is_instance_valid(_player_walker):
		_player_walker = PlayerWalker.new()
		_player_walker.name = "PlayerWalker"
		_player_walker.set_force_no_rom(_force_fallback)
		_player_walker.set_step_evaluator(Callable(self, "_evaluate_interior_step"))
		_player_walker.step_completed.connect(_on_interior_step_completed)
		_player_walker.door_stepped.connect(_on_interior_door_stepped)
		_player_walker.interact_pressed.connect(_on_interior_interact_pressed)
		if _ysort_layer != null:
			_ysort_layer.add_child(_player_walker)
		else:
			add_child(_player_walker)
	var db = _get_db()
	var sidx := 0
	if db != null and db.is_open() and db.has_method("get_player_sprite_index"):
		sidx = int(db.get_player_sprite_index())
	_player_walker.set_sprite_index(sidx)
	_player_walker.set_force_no_rom(_force_fallback)
	_player_walker.place_at(tile, facing_str)

func switch_floor(new_floor_index: int, spawn_tile: Vector2i, facing_str: String = "S") -> bool:
	var floors: Array = _compiled.get("floors", [])
	if new_floor_index < 0 or new_floor_index >= floors.size():
		return false
	_floor_index = new_floor_index
	var saved_zoom := _zoom_step
	var preserved_walker: PlayerWalker = null
	if _walk_mode and _player_walker != null and is_instance_valid(_player_walker):
		preserved_walker = _player_walker
		if preserved_walker.get_parent() != null:
			preserved_walker.get_parent().remove_child(preserved_walker)
		_player_walker = null
	_rebuild_scene(_cache_dir, _force_fallback)
	_zoom_step = saved_zoom
	if _walk_mode:
		if preserved_walker != null:
			_player_walker = preserved_walker
			if _ysort_layer != null:
				_ysort_layer.add_child(_player_walker)
			else:
				add_child(_player_walker)
		_rebuild_block_mask()
		_spawn_or_place_walker(spawn_tile, facing_str)
		if _camera != null:
			_camera.zoom = Vector2(_zoom_step, _zoom_step)
			_camera.position = _player_walker.get_camera_target()
			_camera.make_current()
		set_process(true)
		persist_indoor_session()
	floor_changed.emit(_floor_index, spawn_tile)
	return true

func persist_indoor_session() -> void:
	if not _walk_mode or _screenshot_active or _player_walker == null:
		return
	var db = _get_db()
	var interior_id := str(_compiled.get("id", ""))
	if db == null or not db.is_open() or not db.has_method("save_player_session") or interior_id.is_empty():
		return
	var ret_area := str(_return_info.get("return_area_id", str(_compiled.get("area_id", ""))))
	var ret_x := int(_return_info.get("return_x", 0))
	var ret_y := int(_return_info.get("return_y", 0))
	var place_id := str(_return_info.get("place_id", "city:washington-dc"))
	db.save_player_session({
		"place_id": place_id,
		"area_id": ret_area,
		"tile_x": ret_x,
		"tile_y": ret_y,
		"facing": _player_walker.facing,
		"interior_id": interior_id,
		"interior_floor": _floor_index,
		"interior_x": _player_walker.grid_pos.x,
		"interior_y": _player_walker.grid_pos.y,
		"return_area_id": ret_area,
		"return_x": ret_x,
		"return_y": ret_y,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	session_changed.emit(interior_id, _floor_index, _player_walker.grid_pos, _player_walker.facing)

func _evaluate_interior_step(from_tile: Vector2i, dir: Vector2i) -> Dictionary:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size():
		return {"action": "blocked", "reason": "wall", "tile": from_tile + dir}
	var fd: Dictionary = floors[_floor_index]
	var w := int(fd["w"])
	var h := int(fd["h"])
	var tiles: PackedByteArray = fd["tiles"]

	# Stepping South off a floor-0 door_mat exits the interior cleanly
	if _floor_index == 0 and dir == Vector2i(0, 1):
		if from_tile.x >= 0 and from_tile.x < w and from_tile.y >= 0 and from_tile.y < h:
			if int(tiles[from_tile.y * w + from_tile.x]) == InteriorTiles.TILE_INT_DOOR_MAT:
				return {"action": "door", "exit_interior": true}

	var to := from_tile + dir
	if InteriorCheck._is_tile_passable(fd, _block_mask, to.x, to.y):
		return {"action": "step", "to": to}
	return {"action": "blocked", "reason": "wall", "tile": to}

func _on_interior_door_stepped(door_info: Dictionary) -> void:
	if bool(door_info.get("exit_interior", false)):
		exit_requested.emit(_return_info.duplicate(true))

func _on_interior_step_completed(tile: Vector2i, info: Dictionary) -> void:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size():
		return
	var fd: Dictionary = floors[_floor_index]
	var floor_by_id: Dictionary = _compiled.get("floor_by_id", {})

	# 1. Stairs & warps
	for tr_key in ["stairs", "warps"]:
		for tr_v in (fd.get(tr_key, []) as Array):
			if not (tr_v is Dictionary):
				continue
			var tr: Dictionary = tr_v
			var at_v: Variant = InteriorMap._parse_vec2i(tr.get("at", null))
			if at_v is Vector2i and (at_v as Vector2i) == tile:
				var to_fid := str(tr.get("to_floor", ""))
				var to_v: Variant = InteriorMap._parse_vec2i(tr.get("to", null))
				if floor_by_id.has(to_fid) and to_v is Vector2i:
					var next_facing := _player_walker.facing if _player_walker != null else "S"
					switch_floor(int(floor_by_id[to_fid]), to_v as Vector2i, next_facing)
					return

	# 2. Gust arrows (Emerald 8 frames/tile = 7.5 tps)
	var w := int(fd["w"])
	var h := int(fd["h"])
	var tiles: PackedByteArray = fd["tiles"]
	if not bool(info.get("slide_end", false)) and tile.x >= 0 and tile.x < w and tile.y >= 0 and tile.y < h:
		var cls := int(tiles[tile.y * w + tile.x])
		if InteriorTiles.is_gust_arrow(cls):
			var dest := InteriorCheck._slide_destination(fd, _block_mask, tile)
			var slide_tiles := absi(dest.x - tile.x) + absi(dest.y - tile.y)
			if dest != tile and slide_tiles > 0 and _player_walker != null:
				_player_walker.start_forced_slide(dest, slide_tiles, {"slide_end": true})
				return

	persist_indoor_session()

func get_dialogue_box() -> Control:
	if _dialogue_box == null or not is_instance_valid(_dialogue_box):
		var dlg_scene := load("res://scenes/dialogue_box.tscn") as PackedScene
		if dlg_scene == null:
			return null
		_dialogue_box = dlg_scene.instantiate() as Control
		_dialogue_box.name = "DialogueBox"
		if _hud_canvas != null:
			_hud_canvas.add_child(_dialogue_box)
		else:
			add_child(_dialogue_box)
		if _dialogue_box.has_signal("closed"):
			_dialogue_box.connect("closed", Callable(self, "_on_interior_dialogue_closed"))
	return _dialogue_box

func open_dialogue(lines: Array, speaker: String = "") -> Control:
	var dlg := get_dialogue_box()
	if dlg == null:
		return null
	if dlg.has_method("open_lines"):
		dlg.open_lines(lines, speaker)
	if _player_walker != null:
		_player_walker.input_enabled = false
	return dlg

func _on_interior_dialogue_closed() -> void:
	if _player_walker != null:
		_player_walker.input_enabled = _walk_mode

static func _opposite_facing(dir_str: String) -> String:
	match dir_str.strip_edges().to_upper():
		"N":
			return "S"
		"S":
			return "N"
		"E":
			return "W"
		"W":
			return "E"
		_:
			return "S"

static func _indoor_role_line(role: String, npc_name: String) -> String:
	match role.strip_edges().to_lower():
		"warden":
			return "The watch holds here. Keep your bearings when the quiet settles in."
		"scholar":
			return "Every ledger we salvaged tells the same story — people left in the middle of an ordinary afternoon."
		"healer":
			return "Rest when you reach the Waypost camp. Long walks in the Distortion wear a team down."
		"merchant", "shop", "quartermaster":
			return "We trade what the city left behind and keep the lamps trimmed for nightfall."
		_:
			return "Glad to see another traveler indoors. The streets outside stay quiet after dusk."

func trigger_interact_for_walker() -> bool:
	if _player_walker == null:
		return false
	return _dispatch_interior_interact(_player_walker.facing_tile(), _player_walker.grid_pos, _player_walker.facing)

func _on_interior_interact_pressed(facing_tile: Vector2i, standing_tile: Vector2i, facing_dir: String) -> void:
	_dispatch_interior_interact(facing_tile, standing_tile, facing_dir)

func _dispatch_interior_interact(facing_tile: Vector2i, _standing_tile: Vector2i, facing_dir: String) -> bool:
	if _dialogue_box != null and is_instance_valid(_dialogue_box) and _dialogue_box.visible:
		return false
	var floors: Array = _compiled.get("floors", [])
	if _floor_index < 0 or _floor_index >= floors.size():
		return false
	var fd: Dictionary = floors[_floor_index]

	# 1. Switches (6 across DC famous interiors)
	for sw_v in (fd.get("switches", []) as Array):
		if not (sw_v is Dictionary):
			continue
		var sw: Dictionary = sw_v
		var sw_at: Variant = InteriorMap._parse_vec2i(sw.get("at", null))
		if sw_at is Vector2i and (sw_at as Vector2i) == facing_tile:
			var opens: Array = sw.get("opens", []) if sw.get("opens") is Array else []
			var opened_list: Array[String] = []
			for gid_v in opens:
				var gid := str(gid_v)
				if gid.is_empty():
					continue
				_open_gates[gid] = true
				opened_list.append(gid)
				if _gate_sprites.has(gid):
					for gsp in (_gate_sprites[gid] as Array):
						if is_instance_valid(gsp):
							(gsp as Sprite2D).visible = false
			_rebuild_block_mask()
			show_toast("A distant latch clicks open.")
			switch_toggled.emit(str(sw.get("id", "")), opened_list)
			return true

	# 2. Indoor Signs (100 signs across DC interiors)
	for sg_v in (fd.get("signs", []) as Array):
		if not (sg_v is Dictionary):
			continue
		var sg: Dictionary = sg_v
		var sg_at: Variant = InteriorMap._parse_vec2i(sg.get("at", null))
		if sg_at is Vector2i and (sg_at as Vector2i) == facing_tile:
			open_dialogue([str(sg.get("text", ""))])
			return true

	# 3. Indoor NPCs (25 NPCs across DC interiors; turns toward player)
	if _npc_entries_by_pos.has(facing_tile):
		var entry: Dictionary = _npc_entries_by_pos[facing_tile]
		var npc: Dictionary = entry.get("npc", {})
		var nsp = entry.get("sprite", null)
		var opp := _opposite_facing(facing_dir)
		npc["facing"] = opp
		if nsp != null and is_instance_valid(nsp):
			(nsp as Sprite2D).texture = _get_npc_texture(
				str(npc.get("role", "talk")),
				str(npc.get("sprite", "")),
				opp,
				_force_fallback,
				_cache_dir
			)
		var nlines: Array = npc.get("lines", []) if npc.get("lines") is Array else []
		var nname := str(npc.get("name", "Resident"))
		if nlines.is_empty():
			nlines = [_indoor_role_line(str(npc.get("role", "talk")), nname)]
		open_dialogue(nlines, nname)
		return true

	# 4. Indoor Items (50 items across DC interiors; persisted in collected_item & removed immediately)
	if _item_defs_by_pos.has(facing_tile):
		var it_d: Dictionary = _item_defs_by_pos[facing_tile]
		var interior_id := str(_compiled.get("id", ""))
		var floor_id := str(fd.get("floor_id", str(_floor_index)))
		var ikey := indoor_item_key(interior_id, floor_id, it_d)
		if not ikey.is_empty() and not _collected_item_keys.has(ikey):
			mark_indoor_item_collected(facing_tile)
			open_dialogue(["Found %s!" % str(it_d.get("name", "Item"))])
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not _walk_mode or _screenshot_active or _camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var cur_idx := WALK_ZOOM_STEPS.size() - 1
			for i in range(WALK_ZOOM_STEPS.size()):
				if is_equal_approx(_zoom_step, float(WALK_ZOOM_STEPS[i])):
					cur_idx = i
					break
			var delta_i := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			var next_idx := clampi(cur_idx + delta_i, 0, WALK_ZOOM_STEPS.size() - 1)
			_zoom_step = float(WALK_ZOOM_STEPS[next_idx])
			_camera.zoom = Vector2(_zoom_step, _zoom_step)
			get_viewport().set_input_as_handled()

func setup_screenshot(path: String, zoom_val: float = 1.0, frames: int = 10, interior_view_mode: String = "whole") -> void:
	_screenshot_path = path
	_screenshot_frames_left = maxi(2, frames)
	_screenshot_elapsed_sec = 0.0
	_screenshot_active = true
	var floors: Array = _compiled.get("floors", [])
	var mode := interior_view_mode.strip_edges().to_lower()
	if _banner != null:
		_banner.visible = (mode == "whole" or mode.is_empty())
	if _camera != null and _floor_index >= 0 and _floor_index < floors.size():
		var fd: Dictionary = floors[_floor_index]
		var w := int(fd.get("w", 0))
		var h := int(fd.get("h", 0))
		if mode == "door" and w > 0 and h > 0:
			var door_mats: Array = fd.get("door_mats", [])
			var exit_cx := (float(w) - 1.0) * 0.5
			if not door_mats.is_empty():
				var max_y := -1
				for dm_v in door_mats:
					max_y = maxi(max_y, (dm_v as Vector2i).y)
				var sum_x := 0.0
				var cnt := 0
				for dm_v in door_mats:
					var dm := dm_v as Vector2i
					if dm.y == max_y:
						sum_x += float(dm.x)
						cnt += 1
				if cnt > 0:
					exit_cx = sum_x / float(cnt)
			var x0 := int(floor(exit_cx - 7.0))
			var y0 := h - 9
			_camera.position = Vector2((float(x0) + 7.5) * float(TILE_PX), (float(y0) + 5.0) * float(TILE_PX))
			_camera.zoom = Vector2(zoom_val, zoom_val)
		else:
			_camera.position = Vector2(float(w * TILE_PX) * 0.5, float(h * TILE_PX) * 0.5)
			_camera.zoom = Vector2(zoom_val, zoom_val)
	elif _camera != null:
		_camera.zoom = Vector2(zoom_val, zoom_val)
	set_process(true)

func _process(delta: float) -> void:
	if _walk_mode and not _screenshot_active:
		if _camera != null and _player_walker != null:
			_camera.position = _player_walker.get_camera_target()
		if _world_clock != null:
			_world_clock.tick(delta)
		if _toast_timer > 0.0:
			_toast_timer -= delta
			if _toast_timer <= 0.0 and _toast_panel != null:
				_toast_panel.visible = false
		return
	if not _screenshot_active:
		return
	_screenshot_elapsed_sec += delta
	if _screenshot_elapsed_sec >= screenshot_timeout_sec:
		printerr("[FAIL] interior screenshot timed out after %.1f s" % _screenshot_elapsed_sec)
		get_tree().quit(3)
		return
	if _screenshot_frames_left > 0:
		_screenshot_frames_left -= 1
		return
	_screenshot_active = false
	set_process(false)
	var vp_tex := get_viewport().get_texture()
	if vp_tex == null:
		printerr("[FAIL] viewport texture is null")
		get_tree().quit(1)
		return
	var img := vp_tex.get_image()
	if img == null or img.is_empty():
		printerr("[FAIL] captured interior image is empty")
		get_tree().quit(1)
		return
	var out_dir := _screenshot_path.get_base_dir()
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	var err := img.save_png(_screenshot_path)
	if err != OK:
		printerr("[FAIL] failed to save interior screenshot to %s (err=%d)" % [_screenshot_path, err])
		get_tree().quit(1)
		return
	var fsize := get_floor_size()
	print("INTERIOR_ID=%s FLOOR_INDEX=%d FLOOR_TILES=%dx%d ATLAS=%s" % [
		str(_compiled.get("id", "")),
		_floor_index,
		fsize.x,
		fsize.y,
		_atlas_source_kind,
	])
	print("SCREENSHOT_SAVED " + _screenshot_path)
	get_tree().quit(0)
