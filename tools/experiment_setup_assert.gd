extends Node
## 实验录入页：自动编号、关系二选一、模态数字键盘与只读摘要。

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.language = "zh"
	GameState.experiment_mode = true
	GameState.debug_mode = false
	GameState.station_number = 9
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
	assert(GameState.normalize_dyad_id("1") == "S9-D001", "digits must use the saved station")
	assert(GameState.normalize_dyad_id("01") == "S9-D001", "leading zero normalization failed")
	assert(GameState.normalize_dyad_id("D1").is_empty(), "legacy D-only IDs must be rejected")
	assert(GameState.normalize_dyad_id("S9-D1") == "S9-D001", "canonical station format failed")
	assert(GameState.normalize_dyad_id("S10-D1") == "S10-D001", "station IDs must scale past nine")
	assert(GameState.normalize_dyad_id("S0-D1").is_empty(), "station zero must be rejected")
	assert(GameState.normalize_dyad_id("S2D2").is_empty(), "noncanonical compact IDs must be rejected")
	assert(GameState.normalize_dyad_id("A1").is_empty(), "A must not be a dyad prefix")
	assert(GameState.normalize_dyad_id("B1").is_empty(), "B must not be a dyad prefix")
	assert(GameState.normalize_dyad_id("D001-A").is_empty(), "participant ID must not pass as a dyad ID")
	assert(GameState.default_participant_id("1", "A") == "S9-D001-A", "auto A failed")
	assert(GameState.default_participant_id("2", "B") == "S9-D002-B", "auto B failed")
	assert(GameState.default_a_slot_for_dyad("1") == 0, "odd dyad should put A on P1")
	assert(GameState.default_a_slot_for_dyad("2") == 1, "even dyad should put A on P2")
	assert(not GameState.LOCKABLE_RELATIONS.has("partners"), "partners is no longer a lockable relation")
	assert(not GameState.LOCKABLE_RELATIONS.has("unspecified"), "unspecified must stay unlockable")

	assert(not GameState.lock_experiment_setup("1", "unspecified"), "unspecified relation must be rejected")
	assert(not GameState.lock_experiment_setup("1", "partners"), "partners must be rejected")
	assert(not GameState.lock_experiment_setup("0", "friends"), "non-positive dyad must be rejected")
	assert(GameState.lock_experiment_setup("1", "friends"), "valid dyad and relation should lock")
	assert(GameState.dyad_id == "S9-D001", "dyad normalize mismatch")
	assert(GameState.participant_A == "S9-D001-A", "auto participant A mismatch")
	assert(GameState.participant_B == "S9-D001-B", "auto participant B mismatch")
	assert(GameState.side_assignment == "A=P1;B=P2", "odd dyad side mismatch")
	assert(GameState.experiment_setup_locked, "setup should lock")

	GameState.experiment_setup_locked = false
	assert(GameState.lock_experiment_setup("2", "strangers"), "even dyad should lock")
	assert(GameState.dyad_id == "S9-D002", "even dyad normalize mismatch")
	assert(GameState.participant_A == "S9-D002-A", "even dyad must still auto-fill A")
	assert(GameState.side_assignment == "A=P2;B=P1", "even dyad should assign A to P2")
	assert(GameState.participant_letter_for_slot(0) == "B", "P1 should map to B on even dyads")

	GameState.experiment_setup_locked = false
	GameState.dyad_id = ""
	GameState.participant_A = ""
	GameState.participant_B = ""
	GameState.relation_condition = "unspecified"
	var setup: Node = (
		load("res://scenes/experiment_setup_screen.tscn") as PackedScene
	).instantiate()
	get_tree().root.add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame

	var enter_dyad: Button = setup.find_child("EnterDyad", true, false) as Button
	var strangers: Button = setup.find_child("RelationStrangers", true, false) as Button
	var friends: Button = setup.find_child("RelationFriends", true, false) as Button
	var continue_button: Button = setup.find_child("Continue", true, false) as Button
	var assignment: Control = setup.find_child("AssignmentCard", true, false) as Control
	var dyad_value: Label = setup.find_child("DyadValue", true, false) as Label
	assert(enter_dyad != null and strangers != null and friends != null, "main setup controls missing")
	assert(continue_button != null and assignment != null and dyad_value != null, "summary controls missing")
	assert(setup.find_child("CustomizeIds", true, false) == null, "custom ID button must be removed")
	assert(setup.find_child("RestoreIds", true, false) == null, "restore ID button must be removed")
	assert(setup.find_child("SideAssignment", true, false) == null, "side override button must be removed")
	assert(setup.find_child("Relation", true, false) == null, "cycling relation button must be removed")
	assert(setup.find_child("NumericPad", true, false) == null, "keypad must not stay on the main page")
	assert(setup.find_child("Key_A", true, false) == null, "A key must not exist on the main page")
	assert(setup.find_child("Key_D", true, false) == null, "D key must not exist on the main page")
	assert(assignment.focus_mode == Control.FOCUS_NONE, "assignment card must not take focus")
	assert(assignment.mouse_filter == Control.MOUSE_FILTER_IGNORE, "assignment card must ignore the mouse")
	assert(not (setup.find_child("AssignmentRow", true, false) as Control).visible, "empty assignment must stay hidden")
	assert(dyad_value.focus_mode == Control.FOCUS_NONE, "dyad value must be a label, not a button")
	assert(dyad_value.text == "尚未录入", "empty dyad should say it is not set")
	assert(
		dyad_value.label_settings.font != MenuKit.prepare_data_font(),
		"Chinese empty state must not use the Latin data font",
	)
	assert(continue_button.disabled, "continue must stay disabled until dyad and relation are set")
	assert(setup.get("_dyad_hint").text.contains("组号"), "dyad hint must sit with the dyad field")
	assert(setup.get("_relation_hint").text.is_empty(), "relation hint must wait until a dyad exists")
	var panel: Control = setup.find_child("SetupPanel", true, false) as Control
	var back_button: Button = setup.find_child("Back", true, false) as Button
	var page_actions: HBoxContainer = setup.find_child("PageActions", true, false) as HBoxContainer
	var action_spacer: Control = setup.find_child("ActionSpacer", true, false) as Control
	assert(panel != null and back_button != null, "panel and back button missing")
	assert(page_actions != null and action_spacer != null, "page action layout missing")
	assert(
		continue_button.custom_minimum_size == back_button.custom_minimum_size,
		"page actions must use the same button size",
	)
	assert(
		panel.get_global_rect().has_point(back_button.get_global_rect().position)
		and panel.get_global_rect().has_point(
			back_button.get_global_rect().end - Vector2.ONE
		),
		"back button must stay inside the form panel",
	)
	assert(
		panel.get_global_rect().has_point(continue_button.get_global_rect().position)
		and panel.get_global_rect().has_point(
			continue_button.get_global_rect().end - Vector2.ONE
		),
		"continue must stay inside the form panel",
	)
	assert(back_button.get_global_rect().end.y <= 1080.0, "back button must stay on screen")
	var bottom_gap: float = (
		panel.get_global_rect().end.y - page_actions.get_global_rect().end.y
	)
	assert(bottom_gap >= 24.0 and bottom_gap <= 40.0, "page actions need a balanced bottom margin")
	assert(action_spacer.size.y > 0.0, "flex spacer must push page actions to the panel bottom")

	setup.call("_open_dyad_pad")
	await get_tree().process_frame
	var first_key: Button = setup.find_child("Key_1", true, false) as Button
	var second_key: Button = setup.find_child("Key_2", true, false) as Button
	var third_key: Button = setup.find_child("Key_3", true, false) as Button
	var key_a: Button = setup.find_child("Key_A", true, false) as Button
	var key_b: Button = setup.find_child("Key_B", true, false) as Button
	var key_d: Button = setup.find_child("Key_D", true, false) as Button
	var key_s1: Button = setup.find_child("Key_S1", true, false) as Button
	var key_s2: Button = setup.find_child("Key_S2", true, false) as Button
	var confirm: Button = setup.find_child("Confirm", true, false) as Button
	var cancel: Button = setup.find_child("Cancel", true, false) as Button
	var clear: Button = setup.find_child("Clear", true, false) as Button
	var backspace: Button = setup.find_child("Backspace", true, false) as Button
	var numeric_pad: GridContainer = setup.find_child("NumericPad", true, false) as GridContainer
	var pad_header: HBoxContainer = setup.find_child("PadHeader", true, false) as HBoxContainer
	assert(first_key != null and confirm != null, "modal keypad missing")
	assert(pad_header != null and cancel.get_parent() == pad_header, "cancel must live in the visible header")
	assert(
		key_a == null and key_b == null and key_d == null and key_s1 == null and key_s2 == null,
		"dyad pad must contain no letter keys",
	)
	assert(
		first_key.custom_minimum_size == clear.custom_minimum_size,
		"all keys in the numeric grid must use one width",
	)
	assert(
		absf(third_key.get_global_rect().end.x - numeric_pad.get_global_rect().end.x) <= 1.0
		and is_equal_approx(second_key.size.x, third_key.size.x)
		and is_equal_approx(first_key.size.x, third_key.size.x),
		"numeric keypad columns must fill modal: grid=%s, first=%s, third=%s" % [
			numeric_pad.get_global_rect(),
			first_key.get_global_rect(),
			third_key.get_global_rect(),
		],
	)
	assert(
		backspace.text == "退格"
		and backspace.icon == null
		and str(backspace.get_meta("action_label", "")) == "退格",
		"backspace should use a clear text label instead of a cramped icon",
	)
	for icon_button: Button in [cancel, clear, confirm]:
		assert(
			icon_button.text.is_empty()
			and icon_button.icon != null
			and not str(icon_button.get_meta("action_label", "")).is_empty(),
			"%s must use an icon with an accessible label" % icon_button.name,
		)
		assert(
			icon_button.icon.get_size() == Vector2(32, 32)
			and icon_button.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER,
			"%s icon must share one size and vertical alignment" % icon_button.name,
		)
	assert(
		first_key.get_theme_font("font") == MenuKit.prepare_data_font(),
		"keypad glyphs must use the hyperlegible data font",
	)
	assert(first_key.has_focus(), "opening the pad should focus the first key")
	assert(
		first_key.get_node(first_key.focus_neighbor_top) == cancel
		and cancel.get_node(cancel.focus_neighbor_bottom) == first_key,
		"up from the first keypad row must reach cancel and return",
	)
	assert(
		cancel.mouse_filter == Control.MOUSE_FILTER_STOP
		and cancel.get_global_rect().size == Vector2(56, 56),
		"cancel must expose a full clickable hit target",
	)

	var enter_down: InputEventKey = InputEventKey.new()
	enter_down.keycode = KEY_ENTER
	enter_down.pressed = true
	Input.parse_input_event(enter_down)
	await get_tree().process_frame
	var enter_up: InputEventKey = InputEventKey.new()
	enter_up.keycode = KEY_ENTER
	enter_up.pressed = false
	Input.parse_input_event(enter_up)
	await get_tree().process_frame
	assert(setup.get("_pad_draft") == "1", "Enter should press the focused keypad key")
	setup.call("_pad_append", "A")
	assert(setup.get("_pad_draft") == "1", "participant member A must be rejected by dyad input")
	assert(setup.find_child("DyadPad", true, false) != null, "pressing a key must keep the pad open")

	setup.call("_cancel_dyad_pad")
	await get_tree().process_frame
	assert(setup.find_child("NumericPad", true, false) == null, "cancel must remove the keypad")
	assert(setup.get("_dyad") == "", "cancel must keep the previous empty dyad")

	setup.call("_open_dyad_pad")
	await get_tree().process_frame
	var typed_two: InputEventKey = InputEventKey.new()
	typed_two.keycode = KEY_2
	typed_two.unicode = 50
	typed_two.pressed = true
	setup.call("_unhandled_key_input", typed_two)
	assert(setup.get("_pad_draft") == "2", "physical typing should append a digit")
	assert(setup.get("_pad_confirm").has_focus(), "physical typing should focus Confirm")
	var confirm_enter: InputEventKey = InputEventKey.new()
	confirm_enter.keycode = KEY_ENTER
	confirm_enter.pressed = true
	setup.call("_unhandled_key_input", confirm_enter)
	await get_tree().process_frame
	assert(setup.find_child("NumericPad", true, false) == null, "Enter on Confirm should close the pad")
	assert(setup.get("_dyad") == "S9-D002", "typed dyad should use the saved station")
	assert(dyad_value.text == "S9-D002", "main page should show the normalized dyad")
	assert((setup.find_child("AssignmentRow", true, false) as Control).visible, "assignment appears after a dyad is entered")
	assert(
		panel.get_global_rect().has_point(back_button.get_global_rect().end - Vector2.ONE)
		and panel.get_global_rect().has_point(
			continue_button.get_global_rect().end - Vector2.ONE
		),
		"expanded form must still contain both page actions",
	)
	assert(
		(setup.find_child("AssignmentBody", true, false) as Label).text.contains("S9-D002-A"),
		"summary must show auto participant A",
	)
	assert(
		(setup.find_child("AssignmentBody", true, false) as Label).text.contains("P2"),
		"even dyad summary must show A on P2",
	)
	assert(continue_button.disabled, "continue still requires a relation")
	assert(setup.get("_dyad_hint").text.is_empty(), "filled dyad should clear its field hint")
	assert(setup.get("_relation_hint").text.contains("关系") or setup.get("_relation_hint").text.contains("朋友"), "relation hint must sit with the relation field")

	setup.call("_open_dyad_pad")
	await get_tree().process_frame
	setup.call("_pad_append", "1")
	setup.call("_pad_append", "2")
	var cancel_action: InputEventAction = InputEventAction.new()
	cancel_action.action = InputHub.UI_CANCEL_ACTION
	cancel_action.pressed = true
	setup.call("_input", cancel_action)
	await get_tree().process_frame
	assert(setup.get("_dyad") == "S9-D002", "gamepad B / cancel should restore the previous dyad")

	setup.call("_open_dyad_pad")
	await get_tree().process_frame
	setup.call("_pad_clear")
	setup.call("_pad_append", "1")
	var done_joy: InputEventJoypadButton = InputEventJoypadButton.new()
	done_joy.button_index = JOY_BUTTON_START
	done_joy.pressed = true
	setup.call("_input", done_joy)
	await get_tree().process_frame
	assert(setup.get("_dyad") == "S9-D001", "gamepad Start should confirm with saved station")
	assert(
		(setup.find_child("AssignmentBody", true, false) as Label).text.contains("P1"),
		"odd dyad summary must show A on P1",
	)

	setup.call("_open_dyad_pad")
	await get_tree().process_frame
	setup.call("_pad_clear")
	setup.call("_pad_append", "3")
	setup.call("_confirm_dyad_pad")
	await get_tree().process_frame
	assert(setup.get("_dyad") == "S9-D003", "saved station must be applied automatically")

	setup.call("_select_relation", "friends")
	assert(not continue_button.disabled, "continue should enable after dyad and relation")
	assert(setup.get("_dyad_hint").text.is_empty(), "ready form should clear the dyad hint")
	assert(setup.get("_relation_hint").text.is_empty(), "ready form should clear the relation hint")
	assert(friends.button_pressed and not strangers.button_pressed, "friends should be the selected choice")
	var selected_style: StyleBoxFlat = friends.get_theme_stylebox("pressed") as StyleBoxFlat
	var normal_style: StyleBoxFlat = friends.get_theme_stylebox("normal") as StyleBoxFlat
	assert(
		selected_style != null
		and normal_style != null
		and selected_style.bg_color != normal_style.bg_color
		and selected_style.get_border_width(SIDE_LEFT) > normal_style.get_border_width(SIDE_LEFT),
		"selected relation must have a clearly different fill and border",
	)

	assert(setup.call("_can_continue"), "complete form should be ready to lock")
	assert(
		GameState.lock_experiment_setup(setup.get("_dyad"), setup.get("_relation")),
		"complete form should lock",
	)
	assert(GameState.relation_condition == "friends", "locked relation mismatch")
	assert(GameState.participant_A == "S9-D003-A", "lock must write station-scoped auto A")
	assert(GameState.side_assignment == "A=P1;B=P2", "lock must write parity sides")

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
