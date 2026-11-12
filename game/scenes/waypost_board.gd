extends Control

## game/scenes/waypost_board.gd — Waypost Camp Notice Board Overlay (Item 50)
## Contract: docs/design_neighbourhoods_and_caricature.md §2–§4;
##           docs/implementation_plan_dc_trial.md §7.5

signal go_requested(area_id: String)
signal state_changed(place_id: String)
signal closed()

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

var _place_id: String = ""
var _db_override = null
var _row_info_by_area: Dictionary = {}

@onready var title_label: Label = $BoardPanel/Margin/RootVBox/Header/TitleLabel
@onready var status_label: Label = $BoardPanel/Margin/RootVBox/Header/StatusLabel
@onready var close_button: Button = $BoardPanel/Margin/RootVBox/Header/CloseButton
@onready var rows_vbox: VBoxContainer = $BoardPanel/Margin/RootVBox/Scroll/RowsVBox

func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if not _place_id.is_empty():
		refresh()

func _get_db():
	if _db_override != null:
		return _db_override
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.has_node("DB"):
		return tree.root.get_node("DB")
	return null

func _resolve_city_name(place_id: String) -> String:
	for p_var in RevealEngine.load_places():
		if p_var is Dictionary and str((p_var as Dictionary).get("id", "")) == place_id:
			return str((p_var as Dictionary).get("name", place_id))
	return place_id

func open_for_place(place_id: String, db_override = null) -> void:
	_place_id = place_id
	_db_override = db_override
	visible = true
	refresh()

func get_status_text() -> String:
	return status_label.text if status_label != null else ""

func get_row_info(area_id: String) -> Dictionary:
	return (_row_info_by_area.get(area_id, {}) as Dictionary).duplicate(true)

func refresh() -> void:
	_row_info_by_area.clear()
	if rows_vbox == null:
		return
	for child in rows_vbox.get_children():
		rows_vbox.remove_child(child)
		child.queue_free()

	if _place_id.is_empty():
		return

	var db = _get_db()
	var city_dict: Dictionary = Neighbourhoods.city(_place_id)
	if city_dict.is_empty():
		return

	var city_name := _resolve_city_name(_place_id)
	if title_label != null:
		title_label.text = city_name

	var fp_left := NeighbourhoodProgress.first_picks_left(db, _place_id)
	var p_left := NeighbourhoodProgress.picks_left(db, _place_id)
	var is_complete := NeighbourhoodProgress.city_complete(db, _place_id)
	var openable_list := NeighbourhoodProgress.openable(db, _place_id)
	var openable_set: Dictionary = {}
	for oid in openable_list:
		openable_set[oid] = true

	var status_parts: Array[String] = []
	if fp_left > 0:
		status_parts.append("Choose %d more to start" % fp_left)
	elif is_complete and p_left == 0:
		status_parts.append("City complete")
	else:
		status_parts.append("Picks: %d" % p_left)
		if is_complete:
			status_parts.append("City complete")
	if status_label != null:
		status_label.text = " · ".join(PackedStringArray(status_parts))

	var states_by_id: Dictionary = {}
	if db != null and db.is_open():
		for r_var in db.get_neighbourhood_states(_place_id):
			if r_var is Dictionary:
				var r: Dictionary = r_var
				states_by_id[str(r.get("area_id", ""))] = r

	var camp_dict: Dictionary = city_dict.get("camp", {}) if city_dict.get("camp") is Dictionary else {}
	var camp_id := str(camp_dict.get("id", ""))
	var is_demo := NeighbourhoodProgress.is_demo_profile()

	var hoods_var: Variant = city_dict.get("neighbourhoods", [])
	if not (hoods_var is Array):
		return

	for h_var in hoods_var:
		if not (h_var is Dictionary):
			continue
		var hood: Dictionary = h_var
		var area_id := str(hood.get("id", ""))
		var area_name := str(hood.get("name", area_id))

		var lm_names: Array[String] = []
		var lms_var: Variant = hood.get("landmarks", [])
		if lms_var is Array:
			for lm_var in lms_var:
				if lm_var is Dictionary:
					var lmn := str((lm_var as Dictionary).get("name", ""))
					if not lmn.is_empty():
						lm_names.append(lmn)
		var lm_joined := " · ".join(PackedStringArray(lm_names))

		var has_row := states_by_id.has(area_id)
		var state_val: int = int((states_by_id[area_id] as Dictionary).get("state", 0)) if has_row else 0
		var is_openable := openable_set.has(area_id)

		var state_text := "Locked"
		var state_color := Color(0.58, 0.63, 0.70, 1.0)
		if state_val >= 3:
			state_text = "Finished ✓"
			state_color = Color(0.98, 0.84, 0.42, 1.0)
		elif has_row:
			state_text = "Open"
			state_color = Color(0.56, 0.90, 0.66, 1.0)
		elif is_openable:
			state_text = "Can open"
			state_color = Color(0.54, 0.80, 0.98, 1.0)

		var zone := str(hood.get("zone", "residential"))
		var types_str := str(NeighbourhoodProgress.ZONE_CARD_TYPES.get(zone, "Normal"))
		var night_str := NeighbourhoodProgress.night_danger(hood)
		var mq: Dictionary = hood.get("main_quest", {}) if hood.get("main_quest") is Dictionary else {}
		var pays_str := str(mq.get("pays", ""))
		var trip_min := NeighbourhoodProgress.trip_minutes(_place_id, camp_id, area_id)

		var card_text := "Types: %s · Night: %s · Pays: %s · Trip: %d min" % [
			types_str, night_str, pays_str, trip_min
		]
		var name_line := "%s — %s" % [area_name, lm_joined] if not lm_joined.is_empty() else area_name

		var row_panel := PanelContainer.new()
		row_panel.name = "Row_" + area_id.replace(":", "_").replace("-", "_")
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.11, 0.14, 0.20, 0.96) if (has_row or is_openable) else Color(0.08, 0.10, 0.14, 0.88)
		row_style.border_width_left = 2
		row_style.border_width_top = 1
		row_style.border_width_right = 1
		row_style.border_width_bottom = 1
		row_style.border_color = state_color if (has_row or is_openable) else Color(0.22, 0.26, 0.33, 0.8)
		row_style.corner_radius_top_left = 4
		row_style.corner_radius_top_right = 4
		row_style.corner_radius_bottom_left = 4
		row_style.corner_radius_bottom_right = 4
		row_style.content_margin_left = 12.0
		row_style.content_margin_right = 12.0
		row_style.content_margin_top = 7.0
		row_style.content_margin_bottom = 7.0
		row_panel.add_theme_stylebox_override("panel", row_style)

		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 12)
		row_panel.add_child(row_hbox)

		var left_vbox := VBoxContainer.new()
		left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_vbox.add_theme_constant_override("separation", 2)
		row_hbox.add_child(left_vbox)

		var name_lbl := Label.new()
		name_lbl.name = "NameLabel"
		name_lbl.text = name_line
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override(
			"font_color",
			Color(0.96, 0.97, 0.99, 1.0) if (has_row or is_openable) else Color(0.68, 0.72, 0.78, 1.0)
		)
		left_vbox.add_child(name_lbl)

		var card_lbl := Label.new()
		card_lbl.name = "CardLabel"
		card_lbl.text = card_text
		card_lbl.add_theme_font_size_override("font_size", 12)
		card_lbl.add_theme_color_override("font_color", Color(0.76, 0.81, 0.88, 0.95))
		left_vbox.add_child(card_lbl)

		var state_lbl := Label.new()
		state_lbl.name = "StateLabel"
		state_lbl.custom_minimum_size = Vector2(105, 0)
		state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state_lbl.text = state_text
		state_lbl.add_theme_font_size_override("font_size", 13)
		state_lbl.add_theme_color_override("font_color", state_color)
		row_hbox.add_child(state_lbl)

		var btn_hbox := HBoxContainer.new()
		btn_hbox.name = "Buttons"
		btn_hbox.add_theme_constant_override("separation", 6)
		row_hbox.add_child(btn_hbox)

		var has_open_btn := false
		var has_go_btn := false
		var has_demo_finish_btn := false

		if is_openable:
			has_open_btn = true
			var open_btn := Button.new()
			open_btn.name = "OpenButton"
			open_btn.text = "Open"
			open_btn.custom_minimum_size = Vector2(68, 30)
			open_btn.add_theme_font_size_override("font_size", 12)
			var captured_open_id := area_id
			open_btn.pressed.connect(func(): _on_open_pressed(captured_open_id))
			btn_hbox.add_child(open_btn)

		if has_row:
			has_go_btn = true
			var go_btn := Button.new()
			go_btn.name = "GoButton"
			go_btn.text = "Go"
			go_btn.custom_minimum_size = Vector2(58, 30)
			go_btn.add_theme_font_size_override("font_size", 12)
			var captured_go_id := area_id
			go_btn.pressed.connect(func(): _on_go_pressed(captured_go_id))
			btn_hbox.add_child(go_btn)

		if is_demo and state_val >= 2 and state_val < 3:
			has_demo_finish_btn = true
			var demo_btn := Button.new()
			demo_btn.name = "DemoFinishButton"
			demo_btn.text = "Mark main quest done (demo)"
			demo_btn.custom_minimum_size = Vector2(190, 30)
			demo_btn.add_theme_font_size_override("font_size", 11)
			var captured_fin_id := area_id
			demo_btn.pressed.connect(func(): _on_demo_finish_pressed(captured_fin_id))
			btn_hbox.add_child(demo_btn)

		rows_vbox.add_child(row_panel)

		_row_info_by_area[area_id] = {
			"name_text": name_line,
			"state_text": state_text,
			"card_text": card_text,
			"has_open": has_open_btn,
			"has_go": has_go_btn,
			"has_demo_finish": has_demo_finish_btn,
		}

func _on_open_pressed(area_id: String) -> void:
	var db = _get_db()
	var res := NeighbourhoodProgress.open(db, area_id)
	if bool(res.get("ok", false)):
		state_changed.emit(_place_id)
		refresh()

func _on_go_pressed(area_id: String) -> void:
	var db = _get_db()
	if NeighbourhoodProgress.enter(db, area_id):
		state_changed.emit(_place_id)
		visible = false
		go_requested.emit(area_id)

func _on_demo_finish_pressed(area_id: String) -> void:
	var db = _get_db()
	var res := NeighbourhoodProgress.finish(db, area_id)
	if bool(res.get("ok", false)):
		state_changed.emit(_place_id)
		refresh()

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
