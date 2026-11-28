extends Node

# starter_pick_test.gd — One-Time Starter City Pick Verification (Item 95 / Decision 86)
# Contract: docs/design_famous_places.md §3.1, docs/agent_execution_guide.md §4

const HomeHubScene := preload("res://scenes/home_hub.tscn")

const TEST_DB_PATH: String = "user://test/starter_pick_test.db"
const TEST_TMP_PATH: String = "user://test/starter_pick_test.db.tmp"
const FIXTURE_DB_PATH: String = "user://test/starter_pick_existing_test.db"
const FIXTURE_TMP_PATH: String = "user://test/starter_pick_existing_test.db.tmp"

const EXPECTED_BODY: String = "Choose the great city nearest your home. The fog lifts there first, and wild Pokémon grow stronger the farther you travel from it."


func _cleanup_file(path: String) -> void:
	for suf in ["", "-wal", "-shm", ".tmp"]:
		var p: String = path + str(suf)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _cleanup() -> void:
	DB.close()
	_cleanup_file(TEST_DB_PATH)
	_cleanup_file(FIXTURE_DB_PATH)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)


func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL [starter_pick_test]: DB.assert_test_safe failed")
		return false
	_cleanup()

	# 1. Fresh profile: StarterPickPanel shows, Distort unavailable, only button is "Washington DC"
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()
	var inv_before := DB.query_rows("SELECT COUNT(*) AS c FROM collected_item;")
	var inv_cnt_before: int = int(inv_before[0]["c"]) if not inv_before.is_empty() else 0

	var hub: Control = HomeHubScene.instantiate()
	add_child(hub)
	var pick_panel := hub.get_node_or_null("UI/StarterPickPanel") as PanelContainer
	var hub_panel := hub.get_node_or_null("UI/Panel") as PanelContainer
	var title_lbl := hub.get_node_or_null("UI/StarterPickPanel/Margin/VBox/TitleLabel") as Label
	var body_lbl := hub.get_node_or_null("UI/StarterPickPanel/Margin/VBox/BodyLabel") as Label
	var cities_vbox := hub.get_node_or_null("UI/StarterPickPanel/Margin/VBox/CitiesVBox") as VBoxContainer
	if pick_panel == null or not pick_panel.visible:
		push_error("FAIL [starter_pick_test]: StarterPickPanel not visible on fresh profile")
		hub.free()
		_cleanup()
		return false
	if hub_panel == null or hub_panel.visible or hub.distort_button == null or not hub.distort_button.disabled:
		push_error("FAIL [starter_pick_test]: Distort must be unavailable while starter pick is pending")
		hub.free()
		_cleanup()
		return false
	if title_lbl == null or title_lbl.text != "Where is home?" or body_lbl == null or body_lbl.text != EXPECTED_BODY:
		push_error("FAIL [starter_pick_test]: StarterPickPanel title/body mismatch")
		hub.free()
		_cleanup()
		return false
	if cities_vbox == null or cities_vbox.get_child_count() != 1:
		push_error("FAIL [starter_pick_test]: Expected exactly 1 ready city button, got %d" % (cities_vbox.get_child_count() if cities_vbox != null else -1))
		hub.free()
		_cleanup()
		return false
	var dc_btn := cities_vbox.get_child(0) as Button
	if dc_btn == null or dc_btn.text != "Washington DC":
		push_error("FAIL [starter_pick_test]: Expected 'Washington DC' button, got '%s'" % (dc_btn.text if dc_btn != null else "<null>"))
		hub.free()
		_cleanup()
		return false

	# 2. Choosing Washington DC sets starter_place, distort_list(starter), camp neighbourhood_state, inventory unchanged
	dc_btn.pressed.emit()
	if DB.get_db_meta("starter_place", "") != "city:washington-dc":
		push_error("FAIL [starter_pick_test]: starter_place meta not set to city:washington-dc")
		hub.free()
		_cleanup()
		return false
	var d_entry := DB.get_distort_entry("city:washington-dc")
	if d_entry.is_empty() or str(d_entry.get("reason", "")) != "starter":
		push_error("FAIL [starter_pick_test]: expected distort_list starter entry, got %s" % str(d_entry))
		hub.free()
		_cleanup()
		return false
	var camp_row := DB.get_neighbourhood_state("camp:washington-dc")
	if camp_row.is_empty():
		push_error("FAIL [starter_pick_test]: camp:washington-dc neighbourhood_state row missing")
		hub.free()
		_cleanup()
		return false
	var inv_after := DB.query_rows("SELECT COUNT(*) AS c FROM collected_item;")
	var inv_cnt_after: int = int(inv_after[0]["c"]) if not inv_after.is_empty() else 0
	if inv_cnt_after != inv_cnt_before:
		push_error("FAIL [starter_pick_test]: inventory changed during starter pick (%d -> %d)" % [inv_cnt_before, inv_cnt_after])
		hub.free()
		_cleanup()
		return false
	if pick_panel.visible or not hub_panel.visible or hub.distort_button.disabled:
		push_error("FAIL [starter_pick_test]: normal hub buttons did not appear after starter pick")
		hub.free()
		_cleanup()
		return false
	remove_child(hub)
	hub.free()

	# 3. After relaunch: no starter panel, and choosing again is refused
	DB.close()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()
	var hub2: Control = HomeHubScene.instantiate()
	add_child(hub2)
	var pick2 := hub2.get_node_or_null("UI/StarterPickPanel") as PanelContainer
	var panel2 := hub2.get_node_or_null("UI/Panel") as PanelContainer
	if pick2 == null or pick2.visible or panel2 == null or not panel2.visible or hub2.distort_button.disabled:
		push_error("FAIL [starter_pick_test]: relaunch unexpectedly showed starter pick panel")
		hub2.free()
		_cleanup()
		return false
	if hub2.choose_starter_city("city:washington-dc"):
		push_error("FAIL [starter_pick_test]: choose_starter_city must refuse once starter_place is set")
		hub2.free()
		_cleanup()
		return false
	remove_child(hub2)
	hub2.free()

	# 4. Fixture save that already has a starter never sees the panel
	DB.close()
	DB.configure_paths(FIXTURE_DB_PATH, FIXTURE_TMP_PATH)
	DB.init_db()
	DB.set_db_meta("starter_place", "city:washington-dc")
	var hub3: Control = HomeHubScene.instantiate()
	add_child(hub3)
	var pick3 := hub3.get_node_or_null("UI/StarterPickPanel") as PanelContainer
	var panel3 := hub3.get_node_or_null("UI/Panel") as PanelContainer
	if pick3 == null or pick3.visible or panel3 == null or not panel3.visible:
		push_error("FAIL [starter_pick_test]: existing starter fixture saw starter pick panel")
		hub3.free()
		_cleanup()
		return false
	remove_child(hub3)
	hub3.free()

	_cleanup()
	return true
