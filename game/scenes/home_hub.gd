extends Control

# home_hub.gd — Safehouse Home Hub Scene Controller (Item 20 / Decision 86 Item 95)
# Contract: docs/design_famous_places.md §3.1, docs/agent_execution_guide.md §4

const PlayerSprites := preload("res://world/player_sprites.gd")
const WorldClock := preload("res://world/world_clock.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")

signal distort_requested()
signal character_changed(sprite_index: int)
signal starter_chosen(place_id: String)

@onready var room_art: Control = $RoomArt
@onready var hub_panel: PanelContainer = $UI/Panel
@onready var distort_button: Button = $UI/Panel/VBox/DistortButton
@onready var character_button: Button = $UI/Panel/VBox/CharacterButton
@onready var rest_button: Button = $UI/Panel/VBox/RestButton
@onready var pc_box_button: Button = $UI/Panel/VBox/PCBoxButton
@onready var garden_button: Button = $UI/Panel/VBox/GardenButton
@onready var status_label: Label = $UI/Panel/VBox/StatusLabel
@onready var starter_pick_panel: PanelContainer = $UI/StarterPickPanel
@onready var starter_cities_vbox: VBoxContainer = $UI/StarterPickPanel/Margin/VBox/CitiesVBox

func _ready() -> void:
	_sync_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_sync_to_viewport):
		vp.size_changed.connect(_sync_to_viewport)
	if distort_button != null:
		distort_button.pressed.connect(_on_distort_pressed)
	if character_button != null:
		character_button.pressed.connect(_on_character_pressed)

	# Disabled buttons not yet open
	if rest_button != null:
		rest_button.disabled = true
		rest_button.tooltip_text = "Not open yet."
	if pc_box_button != null:
		pc_box_button.disabled = true
		pc_box_button.tooltip_text = "Not open yet."
	if garden_button != null:
		garden_button.disabled = true
		garden_button.tooltip_text = "Not open yet."

	_refresh_character_button()
	_refresh_starter_pick_state()
	_update_hub_status()

func _sync_to_viewport() -> void:
	var vp_size := get_viewport_rect().size
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		if not (get_parent() is Control):
			anchor_left = 0.0
			anchor_top = 0.0
			anchor_right = 0.0
			anchor_bottom = 0.0
			position = Vector2.ZERO
			size = vp_size
		if room_art != null:
			room_art.queue_redraw()

static func get_ready_starter_cities() -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	for p_v in RevealEngine.load_places():
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v
		if str(p.get("kind", "")) != "city":
			continue
		var pid: String = str(p.get("id", "")).strip_edges()
		if pid.is_empty() or not Neighbourhoods.is_ready(pid):
			continue
		var pname: String = str(p.get("name", pid)).strip_edges()
		ready.append({"id": pid, "name": pname})
	return ready

func _needs_starter_pick() -> bool:
	var db_inst = _get_db()
	if db_inst == null or not db_inst.is_open():
		return false
	return str(db_inst.get_db_meta("starter_place", "")).strip_edges().is_empty()

func _refresh_starter_pick_state() -> void:
	var need_pick := _needs_starter_pick()
	if starter_pick_panel != null:
		starter_pick_panel.visible = need_pick
	if hub_panel != null:
		hub_panel.visible = not need_pick
	if distort_button != null:
		distort_button.disabled = need_pick
	if need_pick and starter_cities_vbox != null:
		for ch in starter_cities_vbox.get_children():
			starter_cities_vbox.remove_child(ch)
			ch.queue_free()
		for c_dict in get_ready_starter_cities():
			var pid: String = str(c_dict.get("id", ""))
			var pname: String = str(c_dict.get("name", pid))
			var btn := Button.new()
			btn.name = "StarterCity_" + pid.replace(":", "_")
			btn.text = pname
			btn.custom_minimum_size = Vector2(0, 38)
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(choose_starter_city.bind(pid))
			starter_cities_vbox.add_child(btn)

func choose_starter_city(place_id: String) -> bool:
	var db_inst = _get_db()
	if db_inst == null or not db_inst.is_open():
		return false
	# One choice per save (Decision 86 / design_famous_places.md §3.1)
	if not str(db_inst.get_db_meta("starter_place", "")).strip_edges().is_empty():
		return false
	if not Neighbourhoods.is_ready(place_id):
		return false
	if not db_inst.set_db_meta("starter_place", place_id):
		return false
	RevealEngine.apply(db_inst)
	_refresh_starter_pick_state()
	_update_hub_status()
	starter_chosen.emit(place_id)
	return true

func _refresh_character_button() -> void:
	if character_button == null:
		return
	var db_inst = _get_db()
	var idx := 0
	if db_inst != null and db_inst.is_open() and db_inst.has_method("get_player_sprite_index"):
		idx = int(db_inst.get_player_sprite_index())
	character_button.text = "Character: %s" % PlayerSprites.display_name_for_index(idx)

func toggle_character_sprite() -> int:
	var db_inst = _get_db()
	var cur := 0
	if db_inst != null and db_inst.is_open() and db_inst.has_method("get_player_sprite_index"):
		cur = int(db_inst.get_player_sprite_index())
	var next_idx := 1 - clampi(cur, 0, 1)
	if db_inst != null and db_inst.is_open() and db_inst.has_method("set_player_sprite_index"):
		db_inst.set_player_sprite_index(next_idx)
	_refresh_character_button()
	character_changed.emit(next_idx)
	return next_idx

func _on_character_pressed() -> void:
	toggle_character_sprite()

func _update_hub_status() -> void:
	if status_label == null:
		return
	var db_inst = _get_db()
	if db_inst != null and db_inst.is_open():
		var clk := WorldClock.new()
		clk.load_from_db(db_inst)
		clk.set_running(false)
		var clock_str := "Clock paused (%s %s)" % [clk.format_hhmm(), clk.time_band()]
		var starter_pid := str(db_inst.get_db_meta("starter_place", "")).strip_edges()
		if starter_pid.is_empty():
			var dists = db_inst.get_all_distort_entries()
			for d in dists:
				if d.get("reason", "") == "starter":
					starter_pid = str(d.get("place_id", "")).strip_edges()
					break
		if not starter_pid.is_empty():
			var starter_name := _resolve_place_name(starter_pid)
			status_label.text = "Safehouse Active • %s • Starter City: %s" % [clock_str, starter_name]
		else:
			status_label.text = "Safehouse Active • %s • Starter City pending" % clock_str
	else:
		status_label.text = "Safehouse Active"

static func _resolve_place_name(place_id: String) -> String:
	var pid := place_id.strip_edges()
	if pid.is_empty():
		return ""
	for p_v in RevealEngine.load_places():
		if p_v is Dictionary and str((p_v as Dictionary).get("id", "")) == pid:
			var nm := str((p_v as Dictionary).get("name", "")).strip_edges()
			if not nm.is_empty():
				return nm
	return pid

func _on_distort_pressed() -> void:
	if _needs_starter_pick():
		return
	distort_requested.emit()
	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_town_map"):
		main_node.open_town_map()
	elif get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/town_map.tscn")

func _get_db():
	var root = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("DB"):
		return root.get_node("DB")
	return null
