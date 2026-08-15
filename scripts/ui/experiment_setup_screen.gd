extends Control
## 配对前录入去标识化实验信息。默认只填组号，自动生成 D001-A / D001-B。
## 三个编号栏固定不动，共用一个始终可见的数字/字母键盘。

const RELATIONS: PackedStringArray = [
	"unspecified",
	"strangers",
	"friends",
	"partners",
]
const ShortIdInputControl: Script = preload("res://scripts/ui/short_id_input.gd")
const KEYPAD_COLUMNS: int = 3

var _dyad_input: ShortIdInput
var _participant_a_input: ShortIdInput
var _participant_b_input: ShortIdInput
var _active_input: ShortIdInput
var _relation: String = "unspecified"
var _a_slot: int = 0
var _ids_customized: bool = false
var _side_overridden: bool = false
var _syncing_ids: bool = false
var _relation_button: Button
var _swap_button: Button
var _customize_button: Button
var _restore_button: Button
var _continue_button: Button
var _back_button: Button
var _error_label: Label
var _inputs: Array[ShortIdInput] = []
var _keypad_buttons: Array[Button] = []
var _done_button: Button

func _ready() -> void:
	_load_existing_values()
	_build()

func _load_existing_values() -> void:
	_relation = (
		GameState.relation_condition
		if RELATIONS.has(GameState.relation_condition)
		else "unspecified"
	)
	_a_slot = clampi(GameState.participant_a_slot, 0, 1)
	if not GameState.dyad_id.is_empty():
		_ids_customized = not (
			GameState.is_default_participant_id(GameState.dyad_id, GameState.participant_A, "A")
			and GameState.is_default_participant_id(GameState.dyad_id, GameState.participant_B, "B")
		)
		_side_overridden = GameState.participant_a_slot != GameState.default_a_slot_for_dyad(GameState.dyad_id)

func _build() -> void:
	add_child(MenuKit.make_grass_bg())
	var title: Control = MenuKit.make_pixel_outline_text(
		GameState.ui("实验信息录入", "EXPERIMENT SETUP"), 40, MenuKit.COL_CREAM, 3
	)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-500, 28)
	title.size = Vector2(1000, 58)
	add_child(title)

	var panel: NinePatchRect = MenuKit.make_panel(Vector2(1560, 820))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-780, -380)
	panel.size = Vector2(1560, 820)
	add_child(panel)

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.offset_left = 48
	root_box.offset_right = -48
	root_box.offset_top = 32
	root_box.offset_bottom = -32
	root_box.add_theme_constant_override("separation", 18)
	panel.add_child(root_box)

	var privacy: Label = MenuKit.make_panel_label(
		GameState.ui(
			"只填组号即可。系统生成 D001 / D001-A / D001-B，禁止姓名。",
			"ENTER DYAD NUMBER ONLY. SYSTEM MAKES D001 / D001-A / D001-B. NO NAMES."
		),
		20,
		0.65,
	)
	privacy.autowrap_mode = TextServer.AUTOWRAP_OFF
	root_box.add_child(privacy)

	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 64)
	root_box.add_child(content)

	var ids: VBoxContainer = VBoxContainer.new()
	ids.custom_minimum_size = Vector2(540, 0)
	ids.add_theme_constant_override("separation", 10)
	content.add_child(ids)

	_dyad_input = _make_id_input(
		GameState.ui("组号", "DYAD ID"), GameState.dyad_id
	)
	_participant_a_input = _make_id_input(
		GameState.ui("参与者 A（自动）", "PARTICIPANT A (AUTO)"), GameState.participant_A
	)
	_participant_b_input = _make_id_input(
		GameState.ui("参与者 B（自动）", "PARTICIPANT B (AUTO)"), GameState.participant_B
	)
	_dyad_input.value_changed.connect(func(_value: String) -> void: _on_dyad_changed())
	_participant_a_input.value_changed.connect(func(_value: String) -> void: _mark_ids_customized())
	_participant_b_input.value_changed.connect(func(_value: String) -> void: _mark_ids_customized())
	for input: ShortIdInput in _inputs:
		ids.add_child(input)
	_sync_auto_ids(false)

	ids.add_child(_make_keypad())

	_error_label = MenuKit.make_panel_label("", 20)
	_error_label.add_theme_color_override("font_color", MenuKit.COL_DANGER)
	_error_label.custom_minimum_size = Vector2(0, 36)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ids.add_child(_error_label)

	var settings: VBoxContainer = VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("separation", 12)
	content.add_child(settings)
	settings.add_child(MenuKit.make_title_label(
		GameState.ui("实验分配", "EXPERIMENT ASSIGNMENT"), 28, MenuKit.COL_ACCENT, true
	))

	var protocol_note: Label = MenuKit.make_panel_label(
		GameState.ui(
			"标准协议 %s：一次完成五关。第 3 关记正常协调，第 4 关固定干扰。" % GameState.PROTOCOL_VERSION,
			"PROTOCOL %s: ONE PASS. L3 = COORDINATION, L4 = PERTURBATION." % GameState.PROTOCOL_VERSION
		),
		20,
		0.7,
	)
	protocol_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(protocol_note)

	_relation_button = _make_setting_button(_relation_text())
	_relation_button.name = "Relation"
	_relation_button.pressed.connect(_cycle_relation)
	settings.add_child(_make_labeled_row(
		GameState.ui("关系条件（必选）", "RELATION (REQUIRED)"), _relation_button
	))

	_swap_button = _make_setting_button(_assignment_text())
	_swap_button.name = "SideAssignment"
	_swap_button.pressed.connect(_swap_sides)
	settings.add_child(_make_labeled_row(
		GameState.ui("参与者与侧别", "PARTICIPANT SIDES"), _swap_button
	))

	_customize_button = _make_setting_button(GameState.ui("自定义编号", "CUSTOM IDS"))
	_customize_button.name = "CustomizeIds"
	_customize_button.pressed.connect(_enable_custom_ids)
	settings.add_child(_customize_button)
	_restore_button = _make_setting_button(GameState.ui("恢复自动编号", "RESTORE AUTO IDS"))
	_restore_button.name = "RestoreIds"
	_restore_button.pressed.connect(_restore_auto_ids)
	settings.add_child(_restore_button)

	var locked_note: Label = MenuKit.make_panel_label(
		GameState.ui(
			"组号奇数 A=P1，偶数 A=P2。覆盖仅用于设备故障，最终侧别会写入日志。",
			"ODD DYAD: A=P1. EVEN DYAD: A=P2. OVERRIDE ONLY FOR DEVICE FAULTS."
		),
		20,
		0.6,
	)
	locked_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(locked_note)

	settings.add_child(_make_instruction_block())

	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings.add_child(filler)

	_continue_button = MenuKit.make_big_button(
		GameState.ui("锁定并继续", "LOCK & CONTINUE"), 26, Vector2(440, 84)
	)
	_continue_button.name = "Continue"
	_continue_button.pressed.connect(_continue_to_pairing)
	settings.add_child(_continue_button)
	_back_button = MenuKit.make_compact_button(
		GameState.ui("返回标题", "BACK TO TITLE"), Vector2(440, 56)
	)
	_back_button.name = "Back"
	_back_button.pressed.connect(_go_back)
	settings.add_child(_back_button)

	_wire_page_focus()
	_dyad_input.focus_entry()

func _make_id_input(caption: String, initial: String) -> ShortIdInput:
	var input: ShortIdInput = ShortIdInputControl.new() as ShortIdInput
	input.setup(caption, initial)
	input.editing_changed.connect(func(is_editing: bool) -> void:
		if is_editing:
			_activate_input(input)
		elif _active_input == input:
			_active_input = null
	)
	input.value_changed.connect(func(_value: String) -> void: _refresh_id_error())
	_inputs.append(input)
	return input

## 页面共用数字键盘：始终占位，避免每个编号栏各自弹出一套键。
func _make_keypad() -> VBoxContainer:
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	var grid: GridContainer = GridContainer.new()
	grid.name = "NumericPad"
	grid.columns = KEYPAD_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	wrap.add_child(grid)

	for digit: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var button: Button = _make_key_button(digit)
		button.name = "Key_%s" % digit
		button.pressed.connect(_on_digit_pressed.bind(digit))
		grid.add_child(button)
		_keypad_buttons.append(button)

	for letter: String in ["D", "A", "B"]:
		var letter_button: Button = _make_key_button(letter)
		letter_button.name = "Key_%s" % letter
		letter_button.pressed.connect(_on_digit_pressed.bind(letter))
		grid.add_child(letter_button)
		_keypad_buttons.append(letter_button)

	var clear_button: Button = _make_key_button(GameState.ui("清空", "CLEAR"), 20)
	clear_button.name = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)
	grid.add_child(clear_button)
	_keypad_buttons.append(clear_button)

	var zero_button: Button = _make_key_button("0")
	zero_button.name = "Key_0"
	zero_button.pressed.connect(_on_digit_pressed.bind("0"))
	grid.add_child(zero_button)
	_keypad_buttons.append(zero_button)

	var delete_button: Button = _make_key_button(GameState.ui("删除", "DELETE"), 20)
	delete_button.name = "Backspace"
	delete_button.pressed.connect(_on_backspace_pressed)
	grid.add_child(delete_button)
	_keypad_buttons.append(delete_button)

	_done_button = MenuKit.make_compact_button(
		GameState.ui("完成输入", "DONE"), Vector2(520, 50)
	)
	_done_button.name = "Done"
	_done_button.pressed.connect(_finish_active_input)
	wrap.add_child(_done_button)
	_wire_keypad_focus()
	return wrap

func _make_key_button(text: String, font_size: int = 26) -> Button:
	var button: Button = MenuKit.make_compact_button(text, Vector2(166, 48))
	button.add_theme_font_size_override("font_size", font_size)
	return button

func _activate_input(input: ShortIdInput) -> void:
	_close_other_editors(input)
	_active_input = input
	if not _keypad_buttons.is_empty():
		_keypad_buttons[0].grab_focus.call_deferred()

func _ensure_active_input() -> ShortIdInput:
	if _active_input != null:
		return _active_input
	_dyad_input.begin_editing()
	return _dyad_input

func _on_digit_pressed(digit: String) -> void:
	_ensure_active_input().append_digit(digit)

func _on_clear_pressed() -> void:
	_ensure_active_input().clear_value()

func _on_backspace_pressed() -> void:
	_ensure_active_input().backspace()

func _finish_active_input() -> void:
	if _active_input != null:
		_active_input.finish_editing()

## A/B 编号实时查重：组号可独立，但两名参与者不能共用同一序号。
func _refresh_id_error() -> void:
	if _error_label == null or _participant_a_input == null or _participant_b_input == null:
		return
	var clean_a: String = GameState.sanitize_experiment_id(_participant_a_input.value)
	var clean_b: String = GameState.sanitize_experiment_id(_participant_b_input.value)
	if not clean_a.is_empty() and not clean_b.is_empty() and clean_a == clean_b:
		_error_label.text = GameState.ui(
			"参与者 A 与 B 的编号不能相同。",
			"PARTICIPANT A AND B IDS MUST DIFFER.",
		)
		return
	_error_label.text = ""

## 面板内固定操作说明：动作在左、按键在右。
func _make_instruction_block() -> VBoxContainer:
	var block: VBoxContainer = VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var heading: Label = MenuKit.make_panel_label(
		GameState.ui("操作说明", "CONTROLS"), 22
	)
	heading.add_theme_color_override("font_color", MenuKit.COL_ACCENT)
	block.add_child(heading)
	block.add_child(_make_instruction_row(
		GameState.ui("选择 / 确认", "SELECT / CONFIRM"),
		GameState.ui("回车键  ·  手柄 A", "ENTER  ·  GAMEPAD A"),
	))
	block.add_child(_make_instruction_row(
		GameState.ui("删除一位", "DELETE ONE DIGIT"),
		GameState.ui("退格键  ·  手柄 B", "BACKSPACE  ·  GAMEPAD B"),
	))
	block.add_child(_make_instruction_row(
		GameState.ui("清空 / 完成", "CLEAR / DONE"),
		GameState.ui("手柄 X  ·  START", "GAMEPAD X  ·  START"),
	))
	return block

func _make_instruction_row(action: String, controls: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var action_label: Label = MenuKit.make_panel_label(action, 19, 0.68)
	action_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(action_label)
	var controls_label: Label = MenuKit.make_panel_label(controls, 19)
	controls_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(controls_label)
	return row

func _make_setting_button(text: String) -> Button:
	return MenuKit.make_compact_button(text, Vector2(390, 60))

func _make_labeled_row(caption: String, button: Button) -> VBoxContainer:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(MenuKit.make_panel_label(caption, 22))
	row.add_child(button)
	return row

func _close_other_editors(active: ShortIdInput) -> void:
	for input: ShortIdInput in _inputs:
		if input != active and input.editing:
			input.finish_editing()

func _on_dyad_changed() -> void:
	if _syncing_ids:
		return
	var normalized: String = GameState.normalize_dyad_id(_dyad_input.value)
	if not normalized.is_empty() and normalized != _dyad_input.value:
		_syncing_ids = true
		_dyad_input.set_value(normalized)
		_syncing_ids = false
	_sync_auto_ids(false)

func _mark_ids_customized() -> void:
	if _syncing_ids:
		return
	_ids_customized = true
	_refresh_id_editability()

func _sync_auto_ids(force: bool) -> void:
	if _dyad_input == null:
		return
	var dyad: String = GameState.normalize_dyad_id(_dyad_input.value)
	if (not _ids_customized or force) and _participant_a_input != null and _participant_b_input != null:
		_syncing_ids = true
		_participant_a_input.set_value(GameState.default_participant_id(dyad, "A"))
		_participant_b_input.set_value(GameState.default_participant_id(dyad, "B"))
		_syncing_ids = false
	if not _side_overridden:
		_a_slot = GameState.default_a_slot_for_dyad(dyad)
	if _swap_button != null:
		_swap_button.text = _assignment_text()
	_refresh_id_editability()
	_refresh_id_error()

func _enable_custom_ids() -> void:
	_ids_customized = true
	_refresh_id_editability()
	_participant_a_input.begin_editing()

func _restore_auto_ids() -> void:
	_ids_customized = false
	_side_overridden = false
	_sync_auto_ids(true)

func _refresh_id_editability() -> void:
	if _participant_a_input == null or _participant_b_input == null:
		return
	_participant_a_input.set_editable(_ids_customized)
	_participant_b_input.set_editable(_ids_customized)

func _cycle_relation() -> void:
	_relation = RELATIONS[(RELATIONS.find(_relation) + 1) % RELATIONS.size()]
	_relation_button.text = _relation_text()

func _swap_sides() -> void:
	_a_slot = 1 - _a_slot
	_side_overridden = true
	_swap_button.text = _assignment_text()

func _relation_text() -> String:
	match _relation:
		"strangers":
			return GameState.ui("陌生人", "STRANGERS")
		"friends":
			return GameState.ui("朋友", "FRIENDS")
		"partners":
			return GameState.ui("伴侣", "PARTNERS")
		_:
			return GameState.ui("未指定", "UNSPECIFIED")

func _assignment_text() -> String:
	var sides: String = (
		GameState.ui("A=P1 左屏 · B=P2 右屏", "A=P1 LEFT · B=P2 RIGHT")
		if _a_slot == 0
		else GameState.ui("B=P1 左屏 · A=P2 右屏", "B=P1 LEFT · A=P2 RIGHT")
	)
	if _side_overridden:
		return "%s · %s" % [sides, GameState.ui("已覆盖", "OVERRIDDEN")]
	return "%s · %s" % [sides, GameState.ui("按组号奇偶", "BY DYAD PARITY")]

func _continue_to_pairing() -> void:
	_finish_active_input()
	var clean_dyad: String = GameState.normalize_dyad_id(_dyad_input.value)
	var clean_a: String = GameState.sanitize_experiment_id(_participant_a_input.value)
	var clean_b: String = GameState.sanitize_experiment_id(_participant_b_input.value)
	if clean_a.is_empty():
		clean_a = GameState.default_participant_id(clean_dyad, "A")
	if clean_b.is_empty():
		clean_b = GameState.default_participant_id(clean_dyad, "B")
	if clean_dyad.is_empty():
		_error_label.text = GameState.ui(
			"请填写有效组号，例如 1 或 D001。",
			"ENTER A VALID DYAD NUMBER, SUCH AS 1 OR D001.",
		)
		return
	if _relation == "unspecified":
		_error_label.text = GameState.ui(
			"请选择关系条件（陌生人 / 朋友 / 伴侣）。未指定不能进入正式数据。",
			"CHOOSE STRANGERS, FRIENDS, OR PARTNERS. UNSPECIFIED IS NOT ALLOWED.",
		)
		return
	if clean_a == clean_b:
		_error_label.text = GameState.ui(
			"参与者 A 与 B 的编号不能相同。",
			"PARTICIPANT A AND B IDS MUST DIFFER.",
		)
		return
	var locked: bool = GameState.lock_experiment_setup(
		clean_dyad,
		clean_a,
		clean_b,
		_relation,
		_a_slot,
	)
	if not locked:
		_error_label.text = GameState.ui(
			"实验信息无效，请检查组号、A/B 编号与关系条件。",
			"SETUP IS INVALID. CHECK DYAD ID, A/B IDS, AND RELATION.",
		)
		return
	InputHub.clear_slots()
	SceneDirector.go_to("res://scenes/pairing_screen.tscn")

func _go_back() -> void:
	SceneDirector.go_to("res://scenes/title_screen.tscn")

func _has_active_editor() -> bool:
	for input: ShortIdInput in _inputs:
		if input.editing:
			return true
	return false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		if _has_active_editor():
			return
		get_viewport().set_input_as_handled()
		_go_back()

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if not _has_active_editor():
			_go_back()

func _wire_page_focus() -> void:
	var controls: Array[Control] = [
		_dyad_input.entry_button(),
		_participant_a_input.entry_button(),
		_participant_b_input.entry_button(),
		_relation_button,
		_swap_button,
		_customize_button,
		_restore_button,
		_continue_button,
		_back_button,
	]
	for index: int in controls.size():
		var previous: Control = controls[posmod(index - 1, controls.size())]
		var next: Control = controls[(index + 1) % controls.size()]
		controls[index].focus_neighbor_top = controls[index].get_path_to(previous)
		controls[index].focus_neighbor_bottom = controls[index].get_path_to(next)
	_participant_b_input.entry_button().focus_neighbor_bottom = (
		_participant_b_input.entry_button().get_path_to(_keypad_buttons[0])
	)
	if not _keypad_buttons.is_empty():
		_keypad_buttons[0].focus_neighbor_top = (
			_keypad_buttons[0].get_path_to(_participant_b_input.entry_button())
		)
		_done_button.focus_neighbor_bottom = (
			_done_button.get_path_to(_relation_button)
		)

func _wire_keypad_focus() -> void:
	var all_buttons: Array[Button] = _keypad_buttons.duplicate()
	all_buttons.append(_done_button)
	for index: int in _keypad_buttons.size():
		var button: Button = _keypad_buttons[index]
		var row: int = index / KEYPAD_COLUMNS
		var column: int = index % KEYPAD_COLUMNS
		var left_index: int = row * KEYPAD_COLUMNS + posmod(column - 1, KEYPAD_COLUMNS)
		var right_index: int = row * KEYPAD_COLUMNS + posmod(column + 1, KEYPAD_COLUMNS)
		var up_index: int = index - KEYPAD_COLUMNS
		var down_index: int = index + KEYPAD_COLUMNS
		if up_index < 0:
			up_index = index
		if down_index >= _keypad_buttons.size():
			down_index = all_buttons.size() - 1
		button.focus_neighbor_left = button.get_path_to(_keypad_buttons[left_index])
		button.focus_neighbor_right = button.get_path_to(_keypad_buttons[right_index])
		button.focus_neighbor_top = button.get_path_to(all_buttons[up_index])
		button.focus_neighbor_bottom = button.get_path_to(all_buttons[down_index])
	_done_button.focus_neighbor_top = _done_button.get_path_to(
		_keypad_buttons[_keypad_buttons.size() - 1]
	)
	_done_button.focus_neighbor_left = _done_button.get_path_to(_done_button)
	_done_button.focus_neighbor_right = _done_button.get_path_to(_done_button)
