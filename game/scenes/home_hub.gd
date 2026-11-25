extends Control

# home_hub.gd — Safehouse Home Hub Scene Controller (Item 20 / plan §5)
# Contract: docs/implementation_plan_famous_places.md §5, docs/agent_execution_guide.md §7.4

const PlayerSprites := preload("res://world/player_sprites.gd")
const WorldClock := preload("res://world/world_clock.gd")

signal distort_requested()
signal pairing_requested()
signal character_changed(sprite_index: int)

@onready var distort_button: Button = $UI/Panel/VBox/DistortButton
@onready var character_button: Button = $UI/Panel/VBox/CharacterButton
@onready var rest_button: Button = $UI/Panel/VBox/RestButton
@onready var pc_box_button: Button = $UI/Panel/VBox/PCBoxButton
@onready var garden_button: Button = $UI/Panel/VBox/GardenButton
@onready var pair_button: Button = $UI/Panel/VBox/PairButton
@onready var status_label: Label = $UI/Panel/VBox/StatusLabel

func _ready() -> void:
	if distort_button != null:
		distort_button.pressed.connect(_on_distort_pressed)
	if character_button != null:
		character_button.pressed.connect(_on_character_pressed)
	if pair_button != null:
		pair_button.pressed.connect(_on_pair_pressed)

	# Disabled buttons marked "coming in Phase 4–7"
	if rest_button != null:
		rest_button.disabled = true
		rest_button.tooltip_text = "Rest — coming in Phase 4–7"
	if pc_box_button != null:
		pc_box_button.disabled = true
		pc_box_button.tooltip_text = "PC Box — coming in Phase 4–7"
	if garden_button != null:
		garden_button.disabled = true
		garden_button.tooltip_text = "Garden — coming in Phase 4–7"

	_refresh_character_button()
	_update_hub_status()

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
		var starter = db_inst.get_distort_entry_by_reason("starter") if db_inst.has_method("get_distort_entry_by_reason") else {}
		if starter.is_empty():
			var dists = db_inst.get_all_distort_entries()
			for d in dists:
				if d.get("reason", "") == "starter":
					starter = d
					break
		if not starter.is_empty():
			status_label.text = "Safehouse Active • %s • Starter City: %s" % [clock_str, str(starter.get("place_id", ""))]
		else:
			status_label.text = "Safehouse Active • %s • Starter City pending" % clock_str
	else:
		status_label.text = "Safehouse Active"

func _on_distort_pressed() -> void:
	distort_requested.emit()
	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_town_map"):
		main_node.open_town_map()
	elif get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/town_map.tscn")

func _on_pair_pressed() -> void:
	pairing_requested.emit()
	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_pairing_screen"):
		main_node.open_pairing_screen()

func _get_db():
	var root = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("DB"):
		return root.get_node("DB")
	return null
