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
const AssetDB := preload("res://rom/asset_db.gd")

const TILE_PX: int = 32
const STAMP_SCALE: float = 2.0

var screenshot_timeout_sec: float = 120.0

var _compiled: Dictionary = {}
var _floor_index: int = 0
var _atlas_source_kind: String = "fallback"
var _stamp_tex_cache: Dictionary = {}
var _npc_tex_cache: Dictionary = {}

var _backdrop: ColorRect = null
var _tile_layer: TileMapLayer = null
var _floor_flat_layer: Node2D = null
var _ysort_layer: Node2D = null
var _ceiling_layer: Node2D = null
var _camera: Camera2D = null
var _hud_canvas: CanvasLayer = null
var _tint_rect: ColorRect = null
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

func get_floor_size() -> Vector2i:
	var floors: Array = _compiled.get("floors", [])
	if _floor_index >= 0 and _floor_index < floors.size():
		var fd: Dictionary = floors[_floor_index]
		return Vector2i(int(fd.get("w", 0)), int(fd.get("h", 0)))
	return Vector2i.ZERO

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
	_rebuild_scene(cache_dir, force_fallback)
	return true

func _clear_scene() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.free()
	_backdrop = null
	_tile_layer = null
	_floor_flat_layer = null
	_ysort_layer = null
	_ceiling_layer = null
	_camera = null
	_hud_canvas = null
	_tint_rect = null
	_title_label = null

func _load_stamp_texture(rel_path: String) -> Texture2D:
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
	_stamp_tex_cache[rel_path] = tex
	return tex

func _get_npc_texture(role: String) -> Texture2D:
	var key := role.to_lower()
	if _npc_tex_cache.has(key):
		return _npc_tex_cache[key]
	var img := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var coat := Color8(66, 108, 176, 255)
	if key == "scholar" or key == "archivist":
		coat = Color8(146, 92, 58, 255)
	elif key == "warden":
		coat = Color8(88, 72, 142, 255)
	var outline := Color8(36, 40, 54, 255)
	var skin := Color8(238, 202, 168, 255)
	var hair := Color8(72, 56, 46, 255)
	# Simple crisp 16x20 front-facing handheld RPG NPC sprite
	for y in range(2, 9):
		for x in range(4, 12):
			var edge := (x == 4 or x == 11 or y == 2 or y == 8)
			if edge:
				img.set_pixel(x, y, outline)
			elif y <= 4:
				img.set_pixel(x, y, hair)
			else:
				img.set_pixel(x, y, skin)
	img.set_pixel(6, 6, outline)
	img.set_pixel(9, 6, outline)
	for y in range(9, 17):
		for x in range(3, 13):
			var edge := (x == 3 or x == 12 or y == 9 or y == 16)
			img.set_pixel(x, y, outline if edge else coat)
	for y in range(17, 20):
		for x in [5, 6, 9, 10]:
			img.set_pixel(x, y, outline)
	var tex := ImageTexture.create_from_image(img)
	_npc_tex_cache[key] = tex
	return tex

func _build_tileset(strip_tex: Texture2D) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	var src := TileSetAtlasSource.new()
	src.texture = strip_tex
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	for c in range(InteriorTiles.CLASS_COUNT):
		src.create_tile(Vector2i(c, 0))
	ts.add_source(src, 0)
	return ts

func _rebuild_scene(cache_dir: String, force_fallback: bool) -> void:
	_clear_scene()
	var floors: Array = _compiled.get("floors", [])
	var fd: Dictionary = floors[_floor_index]
	var w := int(fd["w"])
	var h := int(fd["h"])
	var world_w := float(w * TILE_PX)
	var world_h := float(h * TILE_PX)

	# 1. Void backdrop around room
	_backdrop = ColorRect.new()
	_backdrop.name = "VoidBackdrop"
	_backdrop.color = Color8(12, 14, 20, 255)
	_backdrop.position = Vector2(-2048.0, -2048.0)
	_backdrop.size = Vector2(world_w + 4096.0, world_h + 4096.0)
	_backdrop.z_index = -10
	add_child(_backdrop)

	# 2. Indoor 0..16 base TileMapLayer
	var resolved := InteriorTiles.resolve_atlas_texture(cache_dir, force_fallback)
	var strip_tex: Texture2D = resolved["texture"]
	_atlas_source_kind = str(resolved["source"])

	_tile_layer = TileMapLayer.new()
	_tile_layer.name = "IndoorTileLayer"
	_tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tile_layer.tile_set = _build_tileset(strip_tex)
	_tile_layer.z_index = 0
	var tiles: PackedByteArray = fd["tiles"]
	for y in range(h):
		for x in range(w):
			var cls := int(tiles[y * w + x])
			_tile_layer.set_cell(Vector2i(x, y), 0, Vector2i(cls, 0))
	add_child(_tile_layer)

	# 3. Flat floor layer, Y-sorted upright layer, and Ceiling layer
	_floor_flat_layer = Node2D.new()
	_floor_flat_layer.name = "FloorFlatLayer"
	_floor_flat_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_flat_layer.z_index = 1
	add_child(_floor_flat_layer)

	_ysort_layer = Node2D.new()
	_ysort_layer.name = "YSortPropsLayer"
	_ysort_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ysort_layer.y_sort_enabled = true
	_ysort_layer.z_index = 2
	add_child(_ysort_layer)

	_ceiling_layer = Node2D.new()
	_ceiling_layer.name = "CeilingHangLayer"
	_ceiling_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ceiling_layer.z_index = 4
	add_child(_ceiling_layer)

	for st_v in (fd["stamps"] as Array):
		var st: Dictionary = st_v
		var sid := int(st["stamp_id"])
		var rel_p := str(st["path"])
		var tex := _load_stamp_texture(rel_p)
		if tex == null:
			continue
		var at: Vector2i = st["at"]
		var sw := int(st["w"])
		var sh := int(st["h"])
		var sbase := int(st["base_rows"])

		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.scale = Vector2(STAMP_SCALE, STAMP_SCALE)

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
			# Flat floor prop (int_warp_pad, int_wind_grate)
			sp.position = Vector2(float(at.x * TILE_PX), float(at.y * TILE_PX))
			_floor_flat_layer.add_child(sp)
		else:
			# Upright Y-sorted prop sorted by bottom edge
			sp.position = Vector2(float(at.x * TILE_PX), float((at.y + sh) * TILE_PX))
			sp.offset = Vector2(0.0, float(-sh * 16))
			_ysort_layer.add_child(sp)

	# 4. NPC sprites in Y-sort layer
	for npc_v in (fd["npcs"] as Array):
		var npc: Dictionary = npc_v
		var np_at: Variant = InteriorMap._parse_vec2i(npc.get("at", null))
		if np_at is Vector2i:
			var np_pos: Vector2i = np_at
			var ntex := _get_npc_texture(str(npc.get("role", "talk")))
			var nsp := Sprite2D.new()
			nsp.texture = ntex
			nsp.centered = false
			nsp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			nsp.scale = Vector2(STAMP_SCALE, STAMP_SCALE)
			nsp.position = Vector2(float(np_pos.x * TILE_PX), float((np_pos.y + 1) * TILE_PX))
			nsp.offset = Vector2(0.0, -20.0)
			_ysort_layer.add_child(nsp)

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
		_tint_rect.color = Color(0.20, 0.16, 0.34, 0.18)
		_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_canvas.add_child(_tint_rect)

	var banner := PanelContainer.new()
	banner.position = Vector2(12.0, 10.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.84)
	sb.border_color = Color(0.42, 0.48, 0.60, 0.90)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	banner.add_theme_stylebox_override("panel", sb)

	_title_label = Label.new()
	_title_label.text = "%s  —  %s" % [str(_compiled.get("title", "")), str(fd.get("label", ""))]
	_title_label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.98, 1.0))
	_title_label.add_theme_font_size_override("font_size", 14)
	banner.add_child(_title_label)
	_hud_canvas.add_child(banner)

func setup_screenshot(path: String, zoom_val: float = 1.0, frames: int = 10) -> void:
	_screenshot_path = path
	_screenshot_frames_left = maxi(2, frames)
	_screenshot_elapsed_sec = 0.0
	_screenshot_active = true
	if _camera != null:
		_camera.zoom = Vector2(zoom_val, zoom_val)
	set_process(true)

func _process(delta: float) -> void:
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
