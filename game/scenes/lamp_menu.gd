extends Control

## game/scenes/lamp_menu.gd — Waypost Lamp Fast-Travel Overlay (Item 71)
## Contract: Decision 79 fix (c) (lamps-only fast travel);
##           docs/design_neighbourhoods_and_caricature.md §4.3;
##           docs/implementation_plan_travel_and_time.md §(f)

signal travel_requested(dest_area_id: String, cost_min: int)
signal board_requested()
signal distort_home_requested()
signal closed()

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const WorldClock := preload("res://world/world_clock.gd")

var _place_id: String = ""
var _current_area_id: String = ""
var _db_override = null
var _clock_override = null
var _entries: Array[Dictionary] = []

@onready var center_panel: PanelContainer = $CenterPanel
@onready var title_label: Label = $CenterPanel/Margin/RootVBox/Header/TitleLabel
@onready var subtitle_label: Label = $CenterPanel/Margin/RootVBox/SubtitleLabel
@onready var close_button: Button = $CenterPanel/Margin/RootVBox/Header/CloseButton
@onready var scroll_container: ScrollContainer = $CenterPanel/Margin/RootVBox/Scroll
@onready var rows_vbox: VBoxContainer = $CenterPanel/Margin/RootVBox/Scroll/RowsVBox

func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_update_panel_height):
		vp.size_changed.connect(_update_panel_height)
	if not _place_id.is_empty():
		refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and (ke.keycode == KEY_ESCAPE or ke.keycode == KEY_X):
			_on_close_pressed()
			get_viewport().set_input_as_handled()

func _get_db():
	if _db_override != null:
		return _db_override
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.has_node("DB"):
		return tree.root.get_node("DB")
	return null

func _current_daylight_left(db) -> int:
	if _clock_override != null and _clock_override.has_method("daylight_minutes_left"):
		return int(_clock_override.daylight_minutes_left())
	if db != null and db.is_open() and db.has_method("get_world_clock"):
		var row: Dictionary = db.get_world_clock()
		if not row.is_empty():
			return WorldClock.daylight_minutes_left_for_minute(int(row.get("game_epoch_minutes", WorldClock.DEFAULT_START_MINUTES)))
	return WorldClock.daylight_minutes_left_for_minute(WorldClock.DEFAULT_START_MINUTES)

func open_for_area(place_id: String, current_area_id: String, db_override = null, clock_override = null) -> void:
	_place_id = place_id
	_current_area_id = current_area_id
	_db_override = db_override
	_clock_override = clock_override
	visible = true
	refresh()

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

func can_travel_to(dest_area_id: String) -> bool:
	for e in _entries:
		if str(e.get("action", "")) == "travel" and str(e.get("dest_area_id", "")) == dest_area_id:
			return true
	return false

func select_destination(dest_area_id: String) -> bool:
	for e in _entries:
		if str(e.get("action", "")) == "travel" and str(e.get("dest_area_id", "")) == dest_area_id:
			var cost := int(e.get("cost_min", 1))
			visible = false
			travel_requested.emit(dest_area_id, cost)
			return true
	return false

func refresh() -> void:
	_entries.clear()
	if rows_vbox == null:
		return
	for ch in rows_vbox.get_children():
		rows_vbox.remove_child(ch)
		ch.queue_free()

	if _place_id.is_empty() or _current_area_id.is_empty():
		return

	var db = _get_db()
	var city_dict: Dictionary = Neighbourhoods.city(_place_id)
	if city_dict.is_empty():
		return

	var cur_area: Dictionary = Neighbourhoods.area(_current_area_id)
	var is_camp := (str(cur_area.get("kind", "")) == "camp" or _current_area_id.begins_with("camp:"))
	var camp_dict: Dictionary = city_dict.get("camp", {}) if city_dict.get("camp") is Dictionary else {}
	var camp_id := str(camp_dict.get("id", ""))
	var camp_name := str(camp_dict.get("name", "Wilson Building Camp"))

	if is_camp:
		if title_label != null:
			title_label.text = "%s — Waypost Lamp" % camp_name
		if subtitle_label != null:
			subtitle_label.text = "Use the Notice Board to open areas, or Distort back to your Safehouse."

		_entries.append({"action": "board", "label": "Open Waypost Board"})
		var board_btn := Button.new()
		board_btn.name = "LampBoardButton"
		board_btn.text = "Open Waypost Board"
		board_btn.custom_minimum_size = Vector2(0, 36)
		board_btn.pressed.connect(_on_board_pressed)
		rows_vbox.add_child(board_btn)

		_entries.append({"action": "distort_home", "label": "Distort Home (Safehouse)"})
		var home_btn := Button.new()
		home_btn.name = "LampDistortHomeButton"
		home_btn.text = "Distort Home (Safehouse)"
		home_btn.custom_minimum_size = Vector2(0, 36)
		home_btn.pressed.connect(_on_distort_home_pressed)
		rows_vbox.add_child(home_btn)
		_update_panel_height()
		return

	var cur_name := str(cur_area.get("name", _current_area_id))
	if title_label != null:
		title_label.text = "%s — Waypost Lamp" % cur_name
	if subtitle_label != null:
		subtitle_label.text = "Travel to the camp or any neighbourhood whose lamp is lit."

	var rem_daylight := _current_daylight_left(db)

	# 1. Return to Camp
	if not camp_id.is_empty():
		var camp_cost := NeighbourhoodProgress.trip_minutes(_place_id, _current_area_id, camp_id, false)
		var camp_tag := WorldClock.daylight_tag_for_cost(camp_cost, rem_daylight)
		_add_travel_row(camp_id, "Return to %s" % camp_name, camp_cost, camp_tag)

	# 2. Every entered neighbourhood (state >= 2, excluding current area — §4.3)
	var states_by_id: Dictionary = {}
	if db != null and db.is_open():
		for r_var in db.get_neighbourhood_states(_place_id):
			if r_var is Dictionary:
				var r: Dictionary = r_var
				states_by_id[str(r.get("area_id", ""))] = int(r.get("state", 0))

	var hoods_var: Variant = city_dict.get("neighbourhoods", [])
	if hoods_var is Array:
		for h_var in hoods_var:
			if not (h_var is Dictionary):
				continue
			var h: Dictionary = h_var
			var aid := str(h.get("id", ""))
			if aid.is_empty() or aid == _current_area_id:
				continue
			if int(states_by_id.get(aid, 0)) < 2:
				continue
			var aname := str(h.get("name", aid))
			var cost := NeighbourhoodProgress.trip_minutes(_place_id, _current_area_id, aid, false)
			var tag := WorldClock.daylight_tag_for_cost(cost, rem_daylight)
			_add_travel_row(aid, aname, cost, tag)

	_update_panel_height()

func _update_panel_height() -> void:
	if center_panel == null or rows_vbox == null:
		return
	var row_count := rows_vbox.get_child_count()
	var rows_h := 0.0
	for ch in rows_vbox.get_children():
		if ch is Control:
			var cmin := (ch as Control).get_combined_minimum_size().y
			rows_h += maxf(30.0, cmin)
	if row_count > 1:
		rows_h += float(row_count - 1) * 6.0
	# Chrome: 28 px margins + 4 px panel border + Header (~28) + Subtitle (~18) + HSeparator (~4) + 3*10 separations + 12 px breathing room
	var header_h := 28.0
	var hdr := center_panel.get_node_or_null("Margin/RootVBox/Header") as Control
	if hdr != null:
		header_h = maxf(header_h, hdr.get_combined_minimum_size().y)
	var sub_h := 18.0
	if subtitle_label != null:
		sub_h = maxf(sub_h, subtitle_label.get_combined_minimum_size().y)
	var chrome_h := 28.0 + 4.0 + header_h + sub_h + 4.0 + 30.0 + 12.0
	var vp_h := 640.0
	var vr := get_viewport_rect().size
	if vr.y > 0.0:
		vp_h = vr.y
	elif size.y > 0.0:
		vp_h = size.y
	var max_h := maxf(240.0, vp_h - 48.0)
	var desired_h := clampf(chrome_h + rows_h, 200.0, max_h)
	center_panel.offset_top = -floorf(desired_h * 0.5)
	center_panel.offset_bottom = ceilf(desired_h * 0.5)

func _add_travel_row(dest_area_id: String, label_text: String, cost_min: int, daylight_tag: String) -> void:
	var col := WorldClock.daylight_color(daylight_tag)
	_entries.append({
		"action": "travel",
		"dest_area_id": dest_area_id,
		"label": label_text,
		"cost_min": cost_min,
		"daylight_tag": daylight_tag,
		"daylight_color": col,
	})

	var row_hbox := HBoxContainer.new()
	row_hbox.add_theme_constant_override("separation", 10)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text = label_text
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	row_hbox.add_child(name_lbl)

	var time_lbl := Label.new()
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_lbl.text = "%d min" % cost_min
	time_lbl.add_theme_font_size_override("font_size", 13)
	time_lbl.add_theme_color_override("font_color", col)
	row_hbox.add_child(time_lbl)

	var go_btn := Button.new()
	go_btn.name = "LampGo_" + dest_area_id.replace(":", "_").replace("-", "_")
	go_btn.text = "Go"
	go_btn.custom_minimum_size = Vector2(56, 30)
	var cap_dest := dest_area_id
	go_btn.pressed.connect(func(): select_destination(cap_dest))
	row_hbox.add_child(go_btn)

	rows_vbox.add_child(row_hbox)

func _on_board_pressed() -> void:
	visible = false
	board_requested.emit()

func _on_distort_home_pressed() -> void:
	visible = false
	distort_home_requested.emit()

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
