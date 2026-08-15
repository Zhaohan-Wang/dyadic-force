extends Node
## 实验录入页：D001 规范化、自动 A/B、覆盖/恢复、侧别奇偶与非法字母。

const ShortIdInputControl: Script = preload("res://scripts/ui/short_id_input.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.language = "zh"
	GameState.experiment_mode = true
	GameState.debug_mode = false
	GameState.dyad_id = ""
	GameState.participant_A = ""
	GameState.participant_B = ""
	GameState.relation_condition = "friends"
	GameState.protocol_version = GameState.PROTOCOL_VERSION
	GameState.participant_a_slot = 0
	GameState.side_assignment = "A=P1;B=P2"
	GameState.experiment_setup_locked = false

	assert(GameState.sanitize_experiment_id("组-01 A") == "01A", "sanitizer must keep digits, D/A/B and hyphen")
	assert(GameState.sanitize_experiment_id("P001Q") == "001", "P/Q must be stripped")
	assert(GameState.sanitize_experiment_id("D001-A") == "D001-A", "canonical participant ID must pass")
	assert(GameState.normalize_dyad_id("1") == "D001", "1 should normalize to D001")
	assert(GameState.normalize_dyad_id("01") == "D001", "01 should normalize to D001")
	assert(GameState.normalize_dyad_id("001") == "D001", "001 should normalize to D001")
	assert(GameState.normalize_dyad_id("D001") == "D001", "D001 should stay D001")
	assert(GameState.normalize_dyad_id("D1") == "D001", "D1 should normalize to D001")
	assert(GameState.default_participant_id("1", "A") == "D001-A", "auto A failed")
	assert(GameState.default_participant_id("2", "B") == "D002-B", "auto B failed")
	assert(GameState.default_a_slot_for_dyad("1") == 0, "odd dyad should put A on P1")
	assert(GameState.default_a_slot_for_dyad("2") == 1, "even dyad should put A on P2")
	assert(GameState.is_default_participant_id("D001", "D001-A", "A"), "default A detector failed")

	assert(
		not GameState.lock_experiment_setup("1", "D001-A", "D001-A", "friends", 0),
		"duplicate participant IDs must be rejected",
	)
	assert(
		not GameState.lock_experiment_setup("1", "D001-A", "D001-B", "unspecified", 0),
		"unspecified relation must be rejected",
	)
	assert(
		not GameState.lock_experiment_setup("0", "", "", "friends", 0),
		"non-positive dyad must be rejected",
	)
	assert(
		GameState.lock_experiment_setup("1", "", "", "partners", 0),
		"empty A/B should auto-fill from dyad",
	)
	assert(GameState.dyad_id == "D001", "dyad normalize mismatch")
	assert(GameState.participant_A == "D001-A", "auto participant A mismatch")
	assert(GameState.participant_B == "D001-B", "auto participant B mismatch")
	assert(GameState.experiment_setup_locked, "setup should lock")
	assert(GameState.protocol_version == GameState.PROTOCOL_VERSION, "protocol mismatch")
	assert(GameState.side_assignment == "A=P1;B=P2", "odd dyad side mismatch")

	GameState.experiment_setup_locked = false
	assert(
		GameState.lock_experiment_setup("2", "D002-A", "D002-B", "friends", 0),
		"even dyad with side override should lock",
	)
	assert(GameState.dyad_id == "D002", "even dyad normalize mismatch")
	assert(GameState.side_assignment == "A=P1;B=P2", "explicit side override was not kept")
	assert(GameState.participant_letter_for_slot(0) == "A", "overridden P1 should stay A")

	GameState.experiment_setup_locked = false
	assert(
		GameState.lock_experiment_setup("101", "201", "202", "partners", 1),
		"manual participant override should lock",
	)
	assert(GameState.dyad_id == "D101", "101 should become D101")
	assert(GameState.participant_A == "201", "manual A override mismatch")
	assert(GameState.side_assignment == "A=P2;B=P1", "manual slot override mismatch")
	assert(GameState.participant_letter_for_slot(0) == "B", "P1 should map to B after swap")

	var short_input = ShortIdInputControl.new()
	add_child(short_input)
	short_input.setup("TEST", "12")
	short_input.append_digit("3")
	assert(short_input.value == "123", "virtual digit append failed")
	short_input.append_char("Q")
	assert(short_input.value == "123", "illegal letter Q must be ignored")
	short_input.set_value("D001")
	short_input.append_char("A")
	assert(short_input.value == "D001-A", "A after dyad should insert hyphen")
	short_input.backspace()
	assert(short_input.value == "D001", "backspace should drop the letter and trailing hyphen")
	short_input.clear_value()
	assert(short_input.value.is_empty(), "editing-state X/clear failed")
	short_input.begin_editing()
	assert(short_input.editing, "A/click should enter editing")
	short_input.finish_editing()
	assert(not short_input.editing, "Start/done should leave editing")
	short_input.set_editable(false)
	short_input.begin_editing()
	assert(not short_input.editing, "locked ID field must not enter editing")
	short_input.queue_free()

	GameState.experiment_setup_locked = false
	GameState.dyad_id = ""
	GameState.participant_A = ""
	GameState.participant_B = ""
	var setup: Node = (
		load("res://scenes/experiment_setup_screen.tscn") as PackedScene
	).instantiate()
	get_tree().root.add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	var relation: Button = setup.find_child("Relation", true, false) as Button
	var condition: Button = setup.find_child("Condition", true, false) as Button
	var assignment: Button = setup.find_child("SideAssignment", true, false) as Button
	var continue_button: Button = setup.find_child("Continue", true, false) as Button
	var customize: Button = setup.find_child("CustomizeIds", true, false) as Button
	var restore: Button = setup.find_child("RestoreIds", true, false) as Button
	assert(relation != null and assignment != null, "setup controls missing")
	assert(condition == null, "global condition control must be removed")
	assert(continue_button != null and customize != null and restore != null, "id controls missing")
	var first_key: Button = setup.find_child("Key_1", true, false) as Button
	var key_d: Button = setup.find_child("Key_D", true, false) as Button
	var key_a: Button = setup.find_child("Key_A", true, false) as Button
	var key_b: Button = setup.find_child("Key_B", true, false) as Button
	assert(first_key != null and key_d != null and key_a != null and key_b != null, "shared pad missing D/A/B")
	assert(not first_key.focus_neighbor_right.is_empty(), "pad right focus neighbor missing")
	assert(not first_key.focus_neighbor_bottom.is_empty(), "pad down focus neighbor missing")
	for control: Control in [relation, assignment, customize, restore, continue_button]:
		assert(not control.focus_neighbor_top.is_empty(), "%s top focus missing" % control.name)
		assert(not control.focus_neighbor_bottom.is_empty(), "%s bottom focus missing" % control.name)
	setup.get("_dyad_input").set("value", "1")
	setup.call("_on_dyad_changed")
	assert(setup.get("_dyad_input").get("value") == "D001", "setup should normalize 1 to D001")
	assert(setup.get("_participant_a_input").get("value") == "D001-A", "setup should auto-fill A")
	assert(setup.get("_participant_b_input").get("value") == "D001-B", "setup should auto-fill B")
	assert(setup.get("_a_slot") == 0, "odd dyad should assign A to P1")
	var old_assignment: String = assignment.text
	setup.call("_swap_sides")
	assert(assignment.text != old_assignment, "A/B side swap should update display")
	assert(assignment.text.contains("已覆盖"), "side override should be visible")
	setup.call("_restore_auto_ids")
	assert(setup.get("_a_slot") == 0, "restore should put odd dyad A back on P1")

	setup.call("_enable_custom_ids")
	setup.get("_participant_a_input").set("value", "301")
	setup.get("_participant_b_input").set("value", "301")
	setup.call("_refresh_id_error")
	var error_label: Label = setup.get("_error_label") as Label
	assert(error_label != null and not error_label.text.is_empty(), "duplicate A/B should show error")
	setup.set("_relation", "friends")
	setup.call("_continue_to_pairing")
	assert(not GameState.experiment_setup_locked, "continue must reject identical A/B IDs")
	setup.call("_restore_auto_ids")
	assert(setup.get("_participant_a_input").get("value") == "D001-A", "restore should rebuild A")
	assert(setup.get("_ids_customized") == false, "restore should clear custom flag")

	setup.get("_participant_a_input").set("value", "D001-A")
	setup.get("_participant_b_input").set("value", "D001-B")
	setup.set("_relation", "unspecified")
	setup.call("_refresh_id_error")
	setup.call("_continue_to_pairing")
	assert(not GameState.experiment_setup_locked, "continue must reject unspecified relation")
	assert(error_label.text.contains("关系"), "unspecified relation should show an error")

	var level_select: Node = (
		load("res://scenes/level_select.tscn") as PackedScene
	).instantiate()
	get_tree().root.add_child(level_select)
	await get_tree().process_frame
	assert(
		level_select.find_child("Condition", true, false) == null,
		"level select must not expose an editable condition button",
	)
	var cond_value: Control = level_select.get("_condition_value") as Control
	assert(cond_value != null, "locked protocol value missing")
	assert(cond_value.custom_minimum_size.x > 0.0, "protocol value must report layout width")

	print("experiment_setup_assert OK")
	setup.queue_free()
	level_select.queue_free()
	get_tree().quit(0)
