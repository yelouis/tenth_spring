extends Control

# home_hub.gd — Safehouse Home Hub Scene Controller (Item 20 / plan §5)
# Contract: docs/implementation_plan_famous_places.md §5, docs/agent_execution_guide.md §7.4

signal distort_requested()
signal pairing_requested()

@onready var distort_button: Button = $UI/Panel/VBox/DistortButton
@onready var rest_button: Button = $UI/Panel/VBox/RestButton
@onready var pc_box_button: Button = $UI/Panel/VBox/PCBoxButton
@onready var garden_button: Button = $UI/Panel/VBox/GardenButton
@onready var pair_button: Button = $UI/Panel/VBox/PairButton
@onready var status_label: Label = $UI/Panel/VBox/StatusLabel

func _ready() -> void:
	if distort_button != null:
		distort_button.pressed.connect(_on_distort_pressed)
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

	_update_hub_status()

func _update_hub_status() -> void:
	if status_label == null:
		return
	var db_inst = _get_db()
	if db_inst != null and db_inst.is_open():
		var starter = db_inst.get_distort_entry_by_reason("starter") if db_inst.has_method("get_distort_entry_by_reason") else {}
		if starter.is_empty():
			var dists = db_inst.get_all_distort_entries()
			for d in dists:
				if d.get("reason", "") == "starter":
					starter = d
					break
		if not starter.is_empty():
			status_label.text = "Safehouse Active • Starter City: %s" % str(starter.get("place_id", ""))
		else:
			status_label.text = "Safehouse Active • Starter City pending"
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
