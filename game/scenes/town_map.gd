extends Control

# town_map.gd — Town Map Overview Scene Controller (Item 20 / plan §5)
# Contract: docs/implementation_plan_famous_places.md §5, docs/agent_execution_guide.md §7.4

signal place_selected(place_id: String, waypost_lat: float, waypost_lon: float)
signal back_requested()

const Grid := preload("res://world/grid.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

var _places: Array = []
var _places_by_id: Dictionary = {}
var _markers: Dictionary = {} # place_id -> Button
var _distort_set: Dictionary = {} # place_id -> reason
var _ringed_set: Dictionary = {} # place_id -> true

@onready var map_canvas: Control = $MapCanvas
@onready var markers_container: Control = $MapCanvas/Markers
@onready var back_button: Button = $Header/BackButton
@onready var info_label: Label = $Footer/InfoLabel

func _ready() -> void:
	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)
	load_places_from_config()

func load_places_from_config(config_path: String = "") -> void:
	_places = RevealEngine.load_places(config_path)
	_places_by_id.clear()
	for p in _places:
		_places_by_id[str(p.get("id", ""))] = p
	refresh_markers()

func refresh_markers() -> void:
	_distort_set.clear()
	_ringed_set.clear()

	var db_inst = _get_db()
	if db_inst != null and db_inst.is_open():
		var dist_entries = db_inst.get_all_distort_entries()
		for d in dist_entries:
			_distort_set[str(d.get("place_id", ""))] = str(d.get("reason", "visited"))

		var area_reveals = db_inst.get_all_area_reveals()
		for a in area_reveals:
			if str(a.get("kind", "")) == "city":
				_ringed_set[str(a.get("area_key", ""))] = true

	# Clear previous markers
	if markers_container != null:
		for child in markers_container.get_children():
			child.queue_free()
	_markers.clear()

	var map_rect := Rect2(60, 70, size.x - 120, size.y - 140) if size.x > 200 else Rect2(60, 70, 904, 628)

	for p in _places:
		var pid: String = str(p.get("id", ""))
		var pname: String = str(p.get("name", pid))
		var pkind: String = str(p.get("kind", ""))
		var wp: Dictionary = p.get("waypost", {})
		var w_lat := float(wp.get("lat", 0.0))
		var w_lon := float(wp.get("lon", 0.0))
		var w_name := str(wp.get("name", "Waypost"))

		var is_lit := is_place_lit(pid)
		var is_ringed := is_place_ringed(pid)

		var pos := latlon_to_map_pos(w_lat, w_lon, map_rect)

		var btn := Button.new()
		btn.name = "Marker_" + pid.replace(":", "_").replace("-", "_")
		btn.custom_minimum_size = Vector2(28, 28)
		btn.position = pos - Vector2(14, 14)

		if is_lit:
			btn.disabled = false
			if is_ringed:
				btn.text = "◎"
				btn.tooltip_text = "%s (%s)\nStatus: City Unlocked\nWaypost: %s" % [pname, pkind.capitalize(), w_name]
			else:
				btn.text = "●"
				btn.tooltip_text = "%s (%s)\nStatus: Distort Available\nWaypost: %s" % [pname, pkind.capitalize(), w_name]
			btn.pressed.connect(func(): select_place(pid))
			btn.mouse_entered.connect(func(): _on_marker_hovered(pid))
		else:
			btn.disabled = true
			btn.text = "·"
			btn.tooltip_text = "%s (%s)\nStatus: Locked\nWaypost: %s" % [pname, pkind.capitalize(), w_name]

		if markers_container != null:
			markers_container.add_child(btn)
		_markers[pid] = btn

	if map_canvas != null and map_canvas.has_method("queue_redraw"):
		map_canvas.queue_redraw()

func is_place_lit(place_id: String) -> bool:
	return _distort_set.has(place_id)

func is_place_ringed(place_id: String) -> bool:
	return _ringed_set.has(place_id)

func get_marker(place_id: String) -> Button:
	return _markers.get(place_id, null)

func select_place(place_id: String) -> bool:
	if not is_place_lit(place_id):
		# Locked place cannot be opened (falsifier)
		if info_label != null:
			info_label.text = "Cannot travel to locked place: %s" % place_id
		return false

	var p_info: Dictionary = _places_by_id.get(place_id, {})
	var wp: Dictionary = p_info.get("waypost", {})
	var w_lat := float(wp.get("lat", 0.0))
	var w_lon := float(wp.get("lon", 0.0))

	place_selected.emit(place_id, w_lat, w_lon)

	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_map_view_for_place"):
		main_node.open_map_view_for_place(place_id)
		return true

	if get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://world/map_view.tscn")
		return true

	return true

func _on_marker_hovered(place_id: String) -> void:
	if info_label == null:
		return
	var p_info: Dictionary = _places_by_id.get(place_id, {})
	var pname := str(p_info.get("name", place_id))
	var pkind := str(p_info.get("kind", ""))
	var wp: Dictionary = p_info.get("waypost", {})
	var w_name := str(wp.get("name", "Waypost"))
	var is_lit := is_place_lit(place_id)
	var is_ringed := is_place_ringed(place_id)

	var status_str := "Locked"
	if is_ringed:
		status_str = "City Unlocked (Ringed)"
	elif is_lit:
		status_str = "Distort Available (Lit)"

	info_label.text = "%s (%s) • Waypost: %s • %s" % [pname, pkind.capitalize(), w_name, status_str]

func _on_back_pressed() -> void:
	back_requested.emit()
	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_home_hub"):
		main_node.open_home_hub()
	elif get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/home_hub.tscn")

static func latlon_to_map_pos(lat: float, lon: float, rect: Rect2) -> Vector2:
	var min_wm := Grid.latlon_to_wm(24.0, -125.0)
	var max_wm := Grid.latlon_to_wm(50.0, -66.0)
	var pt_wm := Grid.latlon_to_wm(lat, lon)
	var u := clampf((pt_wm.x - min_wm.x) / (max_wm.x - min_wm.x), 0.0, 1.0)
	var v := clampf((max_wm.y - pt_wm.y) / (max_wm.y - min_wm.y), 0.0, 1.0)
	return Vector2(rect.position.x + u * rect.size.x, rect.position.y + v * rect.size.y)

func _get_db():
	var root = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("DB"):
		return root.get_node("DB")
	return null

var _screenshot_mode: bool = false
var _screenshot_path: String = ""
var _screenshot_target_frames: int = 10
var _screenshot_frames: int = 0

func setup_screenshot(path: String, frames: int = 10) -> void:
	_screenshot_mode = true
	_screenshot_path = path
	_screenshot_target_frames = frames
	_screenshot_frames = 0
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func _on_frame_post_draw() -> void:
	if not _screenshot_mode:
		return
	_screenshot_frames += 1
	if _screenshot_frames >= _screenshot_target_frames:
		_screenshot_mode = false
		var img: Image = get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			var err := img.save_png(_screenshot_path)
			if err != OK:
				printerr("[FAIL] Failed to save screenshot to %s: %d" % [_screenshot_path, err])
				get_tree().quit(1)
				return
			print("SCREENSHOT_SAVED %s" % _screenshot_path.get_file())
			get_tree().quit(0)
		else:
			printerr("[FAIL] Viewport texture returned empty image")
			get_tree().quit(1)

