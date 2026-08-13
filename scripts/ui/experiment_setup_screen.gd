extends Control
## 配对前录入去标识化实验信息，并锁定条件与 A/B 左右分配。
## 三个编号栏固定不动，共用一个始终可见的数字键盘。

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
var _condition: String = "baseline"
var _a_slot: int = 0
var _relation_button: Button
var _condition_button: Button
var _swap_button: Button
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
	_condition = (
		GameState.experiment_condition
		if GameState.EXPERIMENT_CONDITIONS.has(GameState.experiment_condition)
		else "baseline"
	)
	_a_slot = clampi(GameState.participant_a_slot, 0, 1)

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
			"仅输入数字编号，禁止输入姓名（1–16 位）",
			"NUMERIC RESEARCH IDS ONLY — NO NAMES (1-16 DIGITS)"
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
		GameState.ui("去标识化组号", "DYAD ID"), GameState.dyad_id
	)
	_participant_a_input = _make_id_input(
		GameState.ui("参与者 A 编号", "PARTICIPANT A ID"), GameState.participant_A
	)
	_participant_b_input = _make_id_input(
		GameState.ui("参与者 B 编号", "PARTICIPANT B ID"), GameState.participant_B
	)
	for input: ShortIdInput in _inputs:
		ids.add_child(input)

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

	_relation_button = _make_setting_button(_relation_text())
	_relation_button.name = "Relation"
	_relation_button.pressed.connect(_cycle_relation)
	settings.add_child(_make_labeled_row(
		GameState.ui("关系条件", "RELATION"), _relation_button
	))

	_condition_button = _make_setting_button(_condition_text())
	_condition_button.name = "Condition"
	_condition_button.pressed.connect(_cycle_condition)
	settings.add_child(_make_labeled_row(
		GameState.ui("实验条件", "CONDITION"), _condition_button
	))

	_swap_button = _make_setting_button(_assignment_text())
	_swap_button.name = "SideAssignment"
	_swap_button.pressed.connect(_swap_sides)
	settings.add_child(_make_labeled_row(
		GameState.ui("参与者与侧别", "PARTICIPANT SIDES"), _swap_button
	))

	var locked_note: Label = MenuKit.make_panel_label(
		GameState.ui(
			"继续后实验条件将在选关页锁定为只读",
			"CONDITION IS READ-ONLY AFTER CONTINUING"
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

func _cycle_relation() -> void:
	_relation = RELATIONS[(RELATIONS.find(_relation) + 1) % RELATIONS.size()]
	_relation_button.text = _relation_text()

func _cycle_condition() -> void:
	var index: int = GameState.EXPERIMENT_CONDITIONS.find(_condition)
	_condition = GameState.EXPERIMENT_CONDITIONS[(index + 1) % GameState.EXPERIMENT_CONDITIONS.size()]
	_condition_button.text = _condition_text()

func _swap_sides() -> void:
	_a_slot = 1 - _a_slot
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

func _condition_text() -> String:
	return (
		GameState.ui("扰动", "PERTURBATION")
		if _condition == "perturbation"
		else GameState.ui("基线", "BASELINE")
	)

func _assignment_text() -> String:
	return (
		GameState.ui("A=P1 左屏 · B=P2 右屏", "A=P1 LEFT · B=P2 RIGHT")
		if _a_slot == 0
		else GameState.ui("B=P1 左屏 · A=P2 右屏", "B=P1 LEFT · A=P2 RIGHT")
	)

func _continue_to_pairing() -> void:
	_finish_active_input()
	var clean_dyad: String = GameState.sanitize_experiment_id(_dyad_input.value)
	var clean_a: String = GameState.sanitize_experiment_id(_participant_a_input.value)
	var clean_b: String = GameState.sanitize_experiment_id(_participant_b_input.value)
	if clean_dyad.is_empty() or clean_a.is_empty() or clean_b.is_empty():
		_error_label.text = GameState.ui(
			"请填写组号与两名参与者的有效编号（1–16 位数字）。",
			"ENTER VALID NUMERIC IDS FOR THE DYAD AND BOTH PARTICIPANTS.",
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
		_condition,
		_a_slot,
	)
	if not locked:
		_error_label.text = GameState.ui(
			"实验信息无效，请检查后重试。",
			"EXPERIMENT SETUP IS INVALID. PLEASE RETRY.",
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
		_condition_button,
		_swap_button,
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
	_done_button.focus_neighbor_top = _done_button.get_path_to(_keypad_buttons[10])
	_done_button.focus_neighbor_left = _done_button.get_path_to(_done_button)
	_done_button.focus_neighbor_right = _done_button.get_path_to(_done_button)
