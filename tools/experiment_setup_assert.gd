extends Node
## 实验录入页聚焦回归：编号模型、虚拟网格、锁定条件和 A/B 侧别。

const ShortIdInputControl: Script = preload("res://scripts/ui/short_id_input.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.language = "zh"
	GameState.experiment_mode = true
	GameState.debug_mode = false
	GameState.dyad_id = "101"
	GameState.participant_A = "201"
	GameState.participant_B = "202"
	GameState.relation_condition = "friends"
	GameState.experiment_condition = "baseline"
	GameState.participant_a_slot = 0
	GameState.side_assignment = "A=P1;B=P2"
	GameState.experiment_setup_locked = false

	assert(
		GameState.sanitize_experiment_id("组-01 A") == "01",
		"ID sanitizer must retain digits only",
	)
	assert(
		not GameState.lock_experiment_setup("101", "201", "201", "friends", "baseline", 0),
		"duplicate participant IDs must be rejected",
	)
	assert(
		not GameState.lock_experiment_setup("D1", "SAME", "SAME", "friends", "baseline", 0),
		"non-numeric participant IDs must be rejected",
	)
	assert(
		GameState.lock_experiment_setup("101", "201", "202", "partners", "perturbation", 1),
		"valid setup should lock",
	)
	assert(GameState.dyad_id == "101", "numeric dyad ID mismatch")
	assert(GameState.experiment_setup_locked, "condition should be locked")
	assert(GameState.experiment_condition == "perturbation", "condition mismatch")
	assert(GameState.side_assignment == "A=P2;B=P1", "side assignment mismatch")
	assert(GameState.participant_letter_for_slot(0) == "B", "P1 should map to B after swap")

	var short_input = ShortIdInputControl.new()
	add_child(short_input)
	short_input.setup("TEST", "12")
	short_input.append_digit("3")
	assert(short_input.value == "123", "virtual digit append failed")
	short_input.backspace()
	assert(short_input.value == "12", "editing-state B/backspace failed")
	short_input.clear_value()
	assert(short_input.value.is_empty(), "editing-state X/clear failed")
	short_input.begin_editing()
	assert(short_input.editing, "A/click should enter editing")
	short_input.finish_editing()
	assert(not short_input.editing, "Start/done should leave editing")
	short_input.queue_free()

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
	assert(relation != null and condition != null and assignment != null, "setup controls missing")
	assert(continue_button != null, "continue control missing")
	var first_key: Button = setup.find_child("Key_1", true, false) as Button
	assert(first_key != null, "shared numeric pad missing")
	assert(not first_key.focus_neighbor_right.is_empty(), "pad right focus neighbor missing")
	assert(not first_key.focus_neighbor_bottom.is_empty(), "pad down focus neighbor missing")
	for control: Control in [relation, condition, assignment, continue_button]:
		assert(not control.focus_neighbor_top.is_empty(), "%s top focus missing" % control.name)
		assert(not control.focus_neighbor_bottom.is_empty(), "%s bottom focus missing" % control.name)
	var old_assignment: String = assignment.text
	setup.call("_swap_sides")
	assert(assignment.text != old_assignment, "A/B side swap should update display")

	GameState.experiment_setup_locked = false
	GameState.participant_A = ""
	GameState.participant_B = ""
	setup.get("_dyad_input").set("value", "101")
	setup.get("_participant_a_input").set("value", "301")
	setup.get("_participant_b_input").set("value", "301")
	setup.call("_refresh_id_error")
	var error_label: Label = setup.get("_error_label") as Label
	assert(error_label != null and not error_label.text.is_empty(), "duplicate A/B should show error")
	setup.call("_continue_to_pairing")
	assert(not GameState.experiment_setup_locked, "continue must reject identical A/B IDs")
	assert(GameState.participant_A.is_empty(), "failed continue must not write participant A")
	setup.get("_participant_a_input").set("value", "201")
	setup.get("_participant_b_input").set("value", "202")
	setup.call("_refresh_id_error")
	assert(error_label.text.is_empty(), "distinct A/B should clear duplicate error")

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
	assert(cond_value != null, "locked condition value missing")
	assert(cond_value.custom_minimum_size.x > 0.0, "condition value must report layout width")

	print("experiment_setup_assert OK")
	setup.queue_free()
	level_select.queue_free()
	get_tree().quit(0)
