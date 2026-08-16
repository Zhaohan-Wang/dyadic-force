extends Control
## 配对前录入实验信息：组号、关系二选一、核对自动生成的 A/B 与侧别。

const KEYPAD_COLUMNS: int = 3

var _dyad: String = ""
var _relation: String = "unspecified"
var _dyad_value: Label
var _dyad_button: Button
var _strangers_button: Button
var _friends_button: Button
var _assignment_row: HBoxContainer
var _assignment_card: PanelContainer
var _assignment_body: Label
var _dyad_hint: Label
var _relation_hint: Label
var _setup_panel: NinePatchRect
var _continue_button: Button
var _back_button: Button
var _pad_layer: Control
var _pad_draft: String = ""
var _pad_value_label: Label
var _pad_error_label: Label
var _pad_buttons: Array[Button] = []
var _pad_confirm: Button
var _pad_cancel: Button

func _ready() -> void:
	_load_existing_values()
	_build()
	_refresh()
	_dyad_button.grab_focus.call_deferred()

func _load_existing_values() -> void:
	var sequence: int = GameState.dyad_sequence_number(GameState.dyad_id)
	_dyad = str(sequence) if sequence > 0 else ""
	if GameState.LOCKABLE_RELATIONS.has(GameState.relation_condition):
		_relation = GameState.relation_condition

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	var back_hint: HBoxContainer = MenuKit.make_device_hint_row(
		["ESC"],
		["b"],
		GameState.ui("返回", "BACK"),
		44.0,
		InputHub.menu_profile(),
	)
	back_hint.position = Vector2(40, 36)
	add_child(back_hint)

	var title: Control = MenuKit.make_pixel_outline_text(
		GameState.ui("实验信息录入", "EXPERIMENT SETUP"), 40, MenuKit.COL_CREAM, 3
	)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-420, 40)
	title.size = Vector2(840, 58)
	add_child(title)

	var caption: Control = MenuKit.make_world_caption(
		GameState.ui(
			"请使用实验编号，不要填写姓名或其他可识别身份的信息。",
			"USE EXPERIMENT IDS ONLY. DO NOT ENTER NAMES OR OTHER IDENTIFYING INFORMATION.",
		),
		26,
	)
	caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	caption.position = Vector2(-420, 108)
	caption.size = Vector2(840, 36)
	add_child(caption)

	_setup_panel = MenuKit.make_panel(Vector2(880, 390))
	_setup_panel.name = "SetupPanel"
	_setup_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_setup_panel.position = Vector2(-440, 168)
	_setup_panel.size = Vector2(880, 390)
	add_child(_setup_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 32
	root.offset_bottom = -32
	root.add_theme_constant_override("separation", 16)
	_setup_panel.add_child(root)

	root.add_child(_make_labeled_row(GameState.ui("组号", "DYAD"), _make_dyad_row()))
	_dyad_hint = _make_field_hint("DyadHint")
	root.add_child(_indent_field(_dyad_hint))
	root.add_child(_make_labeled_row(GameState.ui("关系", "RELATION"), _make_relation_row()))
	_relation_hint = _make_field_hint("RelationHint")
	root.add_child(_indent_field(_relation_hint))
	_assignment_card = _make_assignment_card()
	_assignment_row = _make_labeled_row(GameState.ui("分配", "SIDES"), _assignment_card)
	_assignment_row.name = "AssignmentRow"
	root.add_child(_assignment_row)

	var action_spacer: Control = Control.new()
	action_spacer.name = "ActionSpacer"
	action_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(action_spacer)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "PageActions"
	actions.add_theme_constant_override("separation", 16)
	root.add_child(actions)
	_continue_button = MenuKit.make_big_button(
		GameState.ui("锁定并继续", "LOCK & CONTINUE"), 24, Vector2(330, 76)
	)
	_continue_button.name = "Continue"
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.pressed.connect(_continue_to_pairing)
	actions.add_child(_continue_button)

	_back_button = MenuKit.make_big_button(
		GameState.ui("返回标题", "BACK TO TITLE"), 24, Vector2(330, 76)
	)
	_back_button.name = "Back"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(_go_back)
	actions.add_child(_back_button)
	_wire_page_focus()

func _make_field_hint(node_name: String) -> Label:
	var hint: Label = MenuKit.make_panel_label("", 18)
	hint.name = node_name
	hint.add_theme_color_override("font_color", MenuKit.COL_DANGER)
	hint.custom_minimum_size = Vector2(0, 22)
	return hint

func _indent_field(field: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(120, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row

func _make_labeled_row(caption: String, field: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var label: Label = MenuKit.make_panel_label(caption, 24)
	label.add_theme_color_override("font_color", MenuKit.COL_ACCENT)
	label.custom_minimum_size = Vector2(120, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row

func _make_dyad_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var readout: PanelContainer = _make_inset_panel(Vector2(0, 64))
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dyad_value = MenuKit.make_panel_label(GameState.ui("尚未录入", "NOT SET"), 30)
	_dyad_value.name = "DyadValue"
	_dyad_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_child(_dyad_value)
	row.add_child(readout)
	_dyad_button = MenuKit.make_compact_button(
		GameState.ui("录入组号", "ENTER DYAD"), Vector2(200, 64)
	)
	_dyad_button.name = "EnterDyad"
	_dyad_button.pressed.connect(_open_dyad_pad)
	row.add_child(_dyad_button)
	return row

func _make_relation_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var relation_group: ButtonGroup = ButtonGroup.new()
	relation_group.allow_unpress = false
	_strangers_button = _make_choice_button(
		GameState.ui("陌生人", "STRANGERS"), "RelationStrangers", relation_group
	)
	_friends_button = _make_choice_button(
		GameState.ui("朋友", "FRIENDS"), "RelationFriends", relation_group
	)
	_strangers_button.pressed.connect(_select_relation.bind("strangers"))
	_friends_button.pressed.connect(_select_relation.bind("friends"))
	row.add_child(_strangers_button)
	row.add_child(_friends_button)
	return row

func _make_choice_button(text: String, node_name: String, group: ButtonGroup) -> Button:
	var button: Button = MenuKit.make_compact_button(text, Vector2(240, 64))
	button.name = node_name
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected: StyleBoxFlat = StyleBoxFlat.new()
	selected.bg_color = Color("f3b45b")
	selected.border_color = MenuKit.COL_ACCENT
	selected.set_border_width_all(6)
	selected.set_corner_radius_all(5)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)
	button.add_theme_color_override("font_pressed_color", MenuKit.COL_INK)
	button.add_theme_color_override("font_hover_pressed_color", MenuKit.COL_INK)
	return button

func _make_inset_panel(min_size: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.focus_mode = Control.FOCUS_NONE
	panel.custom_minimum_size = min_size
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("f3e2c0")
	style.border_color = Color(MenuKit.COL_OUTLINE, 0.22)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_assignment_card() -> PanelContainer:
	var card: PanelContainer = _make_inset_panel(Vector2(0, 112))
	card.name = "AssignmentCard"
	_assignment_body = MenuKit.make_panel_label("", 24, 0.88)
	_assignment_body.name = "AssignmentBody"
	_assignment_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(_assignment_body)
	return card

func _apply_data_font(label: Label, size: int) -> void:
	if label.label_settings != null:
		label.label_settings.font = MenuKit.prepare_data_font()
		label.label_settings.font_size = size

func _select_relation(next_relation: String) -> void:
	_relation = next_relation
	_refresh()

func _composed_dyad() -> String:
	return GameState.normalize_dyad_id(_dyad, _relation)

func _refresh() -> void:
	var has_sequence: bool = not _dyad.is_empty()
	var composed: String = _composed_dyad()
	if has_sequence:
		MenuKit.set_label_text(
			_dyad_value,
			composed if not composed.is_empty() else GameState.format_dyad_sequence(_dyad),
		)
		_apply_data_font(_dyad_value, 32)
		_dyad_value.label_settings.font_color = MenuKit.COL_INK
		_dyad_button.text = GameState.ui("修改组号", "CHANGE DYAD")
	else:
		MenuKit.set_label_text(_dyad_value, GameState.ui("尚未录入", "NOT SET"))
		if _dyad_value.label_settings != null:
			_dyad_value.label_settings.font_size = 30
		_dyad_value.label_settings.font_color = Color(MenuKit.COL_INK, 0.45)
		_dyad_button.text = GameState.ui("录入组号", "ENTER DYAD")

	_strangers_button.set_pressed_no_signal(_relation == "strangers")
	_friends_button.set_pressed_no_signal(_relation == "friends")
	_refresh_assignment()

	var ready: bool = _can_continue()
	_continue_button.disabled = not ready
	_continue_button.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	_set_field_hint(
		_dyad_hint,
		GameState.ui(
			"当前采集站 %d · 请录入组号数字" % GameState.station_number,
			"STATION %d · ENTER THE NUMERIC DYAD SEQUENCE" % GameState.station_number,
		)
		if not has_sequence
		else "",
	)
	_set_field_hint(
		_relation_hint,
		GameState.ui("请选择关系", "CHOOSE A RELATION")
		if has_sequence and _relation == "unspecified"
		else "",
	)
	_wire_page_focus()

func _set_field_hint(hint: Label, text: String) -> void:
	if hint == null:
		return
	MenuKit.set_label_text(hint, text)
	hint.add_theme_color_override("font_color", MenuKit.COL_DANGER)
	hint.visible = not text.is_empty()
	if hint.get_parent() != null:
		hint.get_parent().visible = hint.visible

func _refresh_assignment() -> void:
	var composed: String = _composed_dyad()
	var has_assignment: bool = not composed.is_empty()
	if _assignment_row != null:
		_assignment_row.visible = has_assignment
	if _setup_panel != null:
		var height: float = 520.0 if has_assignment else 390.0
		_setup_panel.custom_minimum_size = Vector2(880, height)
		_setup_panel.size = Vector2(880, height)
	if not has_assignment:
		MenuKit.set_label_text(_assignment_body, "")
		return
	var a_slot: int = GameState.default_a_slot_for_dyad(_dyad)
	var a_side: String = GameState.ui("P1 左屏", "P1 LEFT") if a_slot == 0 else GameState.ui("P2 右屏", "P2 RIGHT")
	var b_side: String = GameState.ui("P2 右屏", "P2 RIGHT") if a_slot == 0 else GameState.ui("P1 左屏", "P1 LEFT")
	MenuKit.set_label_text(
		_assignment_body,
		GameState.ui(
			"A  %s    %s\nB  %s    %s" % [
				GameState.default_participant_id(composed, "A", _relation),
				a_side,
				GameState.default_participant_id(composed, "B", _relation),
				b_side,
			],
			"A  %s    %s\nB  %s    %s" % [
				GameState.default_participant_id(composed, "A", _relation),
				a_side,
				GameState.default_participant_id(composed, "B", _relation),
				b_side,
			],
		),
	)
	_apply_data_font(_assignment_body, 24)

func _can_continue() -> bool:
	return not _composed_dyad().is_empty()

func _open_dyad_pad() -> void:
	if _pad_layer != null:
		return
	_pad_draft = _draft_sequence_digits_from(_dyad)
	_pad_layer = Control.new()
	_pad_layer.name = "DyadPad"
	_pad_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pad_layer)

	var dim: ColorRect = MenuKit.make_dim_overlay(0.5)
	_pad_layer.add_child(dim)

	var sheet: NinePatchRect = MenuKit.make_panel(Vector2(560, 620))
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.position = Vector2(-280, -310)
	sheet.size = Vector2(560, 620)
	_pad_layer.add_child(sheet)

	_pad_cancel = MenuKit.make_compact_button("", Vector2(56, 56))
	_pad_cancel.name = "Cancel"
	_set_pad_action_icon(
		_pad_cancel,
		"cross_dark",
		GameState.ui("取消", "CANCEL"),
		true,
	)
	_pad_cancel.pressed.connect(_cancel_dyad_pad)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 36
	box.offset_right = -36
	box.offset_top = 28
	box.offset_bottom = -28
	box.add_theme_constant_override("separation", 14)
	sheet.add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "PadHeader"
	header.custom_minimum_size = Vector2(0, 56)
	var header_title: Label = MenuKit.make_panel_label(
		GameState.ui("输入组号", "ENTER DYAD NUMBER"), 24
	)
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(header_title)
	header.add_child(_pad_cancel)
	box.add_child(header)

	box.add_child(MenuKit.make_panel_label(
		GameState.ui(
			"当前采集站 %d · 只输入数字，字母由关系自动生成" % GameState.station_number,
			"STATION %d · ENTER DIGITS ONLY. F/S COMES FROM RELATION" % GameState.station_number,
		),
		18,
		0.62,
	))
	_pad_value_label = MenuKit.make_panel_label("", 36)
	_pad_value_label.name = "PadValue"
	_pad_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pad_value_label.custom_minimum_size = Vector2(0, 56)
	_apply_data_font(_pad_value_label, 36)
	box.add_child(_pad_value_label)

	var grid: GridContainer = GridContainer.new()
	grid.name = "NumericPad"
	grid.columns = KEYPAD_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	_pad_buttons.clear()
	for key: String in [
		"1", "2", "3",
		"4", "5", "6",
		"7", "8", "9",
		"BACKSPACE", "0", "CLEAR",
	]:
		var button: Button
		match key:
			"BACKSPACE":
				button = _make_pad_key(
					GameState.ui("退格", "BACKSPACE"),
					18,
				)
				button.name = "Backspace"
				button.tooltip_text = GameState.ui("删除上一位", "DELETE PREVIOUS CHARACTER")
				button.set_meta(
					"action_label",
					GameState.ui("退格", "BACKSPACE"),
				)
				button.pressed.connect(_pad_backspace)
			"CLEAR":
				button = _make_pad_key("", 18)
				button.name = "Clear"
				_set_pad_action_icon(
					button,
					"clear",
					GameState.ui("清空", "CLEAR"),
				)
				button.pressed.connect(_pad_clear)
			_:
				button = _make_pad_key(key)
				button.name = "Key_%s" % key
				button.add_theme_font_override("font", MenuKit.prepare_data_font())
				button.add_theme_font_size_override("font_size", 30)
				button.pressed.connect(_pad_append.bind(key))
		grid.add_child(button)
		_pad_buttons.append(button)

	_pad_confirm = MenuKit.make_compact_button("", Vector2(0, 58))
	_pad_confirm.name = "Confirm"
	_pad_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_pad_action_icon(
		_pad_confirm,
		"check_dark",
		GameState.ui("确认编号", "CONFIRM NUMBER"),
		true,
	)
	_pad_confirm.pressed.connect(_confirm_dyad_pad)
	box.add_child(_pad_confirm)

	_pad_error_label = MenuKit.make_panel_label("", 18)
	_pad_error_label.add_theme_color_override("font_color", MenuKit.COL_DANGER)
	_pad_error_label.custom_minimum_size = Vector2(0, 24)
	box.add_child(_pad_error_label)

	_refresh_pad_value()
	_wire_pad_focus()
	_set_page_interactive(false)
	_pad_buttons[0].grab_focus.call_deferred()

func _make_pad_key(text: String, font_size: int = 26) -> Button:
	var button: Button = MenuKit.make_compact_button(text, Vector2(150, 52))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", font_size)
	return button

func _set_pad_action_icon(
	button: Button,
	icon_name: String,
	label: String,
	use_atlas: bool = false,
) -> void:
	button.text = ""
	button.icon = (
		MenuKit.make_ui_icon_texture(icon_name)
		if use_atlas
		else MenuKit.make_button_icon(icon_name, 2, MenuKit.COL_INK)
	)
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.tooltip_text = label
	button.set_meta("action_label", label)

func _refresh_pad_value() -> void:
	if _pad_value_label == null:
		return
	if _pad_draft.is_empty():
		MenuKit.set_label_text(_pad_value_label, GameState.ui("—", "—"))
	else:
		MenuKit.set_label_text(_pad_value_label, "%s  _" % _pad_draft)
	_apply_data_font(_pad_value_label, 36)

func _pad_append(character: String) -> void:
	var next: String = character.to_upper()
	if next.length() == 1 and next >= "0" and next <= "9":
		if _pad_draft.length() + next.length() > GameState.ID_MAX_LENGTH:
			return
		_pad_draft += next
	else:
		return
	_clear_pad_error()
	_refresh_pad_value()

func _draft_sequence_digits_from(value: String) -> String:
	var sequence: int = GameState.dyad_sequence_number(value)
	return str(sequence) if sequence > 0 else ""

func _pad_backspace() -> void:
	if _pad_draft.is_empty():
		return
	_pad_draft = _pad_draft.left(_pad_draft.length() - 1)
	_clear_pad_error()
	_refresh_pad_value()

func _pad_clear() -> void:
	_pad_draft = ""
	_clear_pad_error()
	_refresh_pad_value()

func _clear_pad_error() -> void:
	if _pad_error_label != null:
		_pad_error_label.text = ""

func _confirm_dyad_pad() -> void:
	var sequence: int = GameState.dyad_sequence_number(_pad_draft)
	if sequence <= 0:
		if _pad_error_label != null:
			_pad_error_label.text = GameState.ui(
				"编号无效，请输入大于 0 的数字",
				"INVALID NUMBER. ENTER A NUMBER GREATER THAN 0",
			)
		return
	_dyad = str(sequence)
	_close_dyad_pad()
	_refresh()
	_dyad_button.grab_focus.call_deferred()

func _cancel_dyad_pad() -> void:
	_close_dyad_pad()
	_dyad_button.grab_focus.call_deferred()

func _close_dyad_pad() -> void:
	if _pad_layer == null:
		return
	_pad_layer.queue_free()
	_pad_layer = null
	_pad_buttons.clear()
	_pad_confirm = null
	_pad_cancel = null
	_pad_value_label = null
	_pad_error_label = null
	_pad_draft = ""
	_set_page_interactive(true)

func _continue_to_pairing() -> void:
	if not _can_continue():
		_refresh()
		return
	if not GameState.lock_experiment_setup(_dyad, _relation):
		_set_field_hint(
			_dyad_hint,
			GameState.ui("实验信息无效，请检查组号。", "SETUP IS INVALID. CHECK THE DYAD NUMBER."),
		)
		return
	InputHub.clear_slots()
	SceneDirector.go_to("res://scenes/pairing_screen.tscn")

func _go_back() -> void:
	if _pad_layer != null:
		_cancel_dyad_pad()
		return
	SceneDirector.go_to("res://scenes/title_screen.tscn")

func _input(event: InputEvent) -> void:
	if _pad_layer != null:
		var joy: InputEventJoypadButton = event as InputEventJoypadButton
		if joy != null and joy.pressed:
			if joy.button_index == JOY_BUTTON_X:
				_pad_clear()
				get_viewport().set_input_as_handled()
				return
			if joy.button_index == JOY_BUTTON_START:
				_confirm_dyad_pad()
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
			_cancel_dyad_pad()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		_go_back()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		if _pad_layer != null:
			_cancel_dyad_pad()
		else:
			_go_back()
		get_viewport().set_input_as_handled()
		return
	if _pad_layer == null:
		return
	if key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
		_pad_backspace()
		get_viewport().set_input_as_handled()
		return
	if (
		(key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)
		and _pad_confirm != null
		and _pad_confirm.has_focus()
	):
		_confirm_dyad_pad()
		get_viewport().set_input_as_handled()
		return
	if key.unicode > 0:
		var typed: String = String.chr(key.unicode).to_upper()
		if typed.length() == 1 and typed >= "0" and typed <= "9":
			if _pad_draft.length() < GameState.ID_MAX_LENGTH:
				_pad_draft += typed
				_clear_pad_error()
				_refresh_pad_value()
			if _pad_confirm != null:
				_pad_confirm.grab_focus()
			get_viewport().set_input_as_handled()

func _set_page_interactive(enabled: bool) -> void:
	for button: Button in [
		_dyad_button,
		_strangers_button,
		_friends_button,
		_continue_button,
		_back_button,
	]:
		if button == null:
			continue
		var can_focus: bool = enabled and not button.disabled
		button.focus_mode = Control.FOCUS_ALL if can_focus else Control.FOCUS_NONE
	if enabled:
		_wire_page_focus()

func _wire_page_focus() -> void:
	if _pad_layer != null:
		return
	var controls: Array[Control] = [
		_dyad_button,
		_strangers_button,
		_friends_button,
	]
	if not _continue_button.disabled:
		controls.append(_continue_button)
	controls.append(_back_button)
	_link_vertical(controls)

func _wire_pad_focus() -> void:
	for index: int in _pad_buttons.size():
		var button: Button = _pad_buttons[index]
		var row: int = index / KEYPAD_COLUMNS
		var column: int = index % KEYPAD_COLUMNS
		var left_index: int = row * KEYPAD_COLUMNS + posmod(column - 1, KEYPAD_COLUMNS)
		var right_index: int = row * KEYPAD_COLUMNS + posmod(column + 1, KEYPAD_COLUMNS)
		var up_index: int = index - KEYPAD_COLUMNS
		var down_index: int = index + KEYPAD_COLUMNS
		button.focus_neighbor_left = button.get_path_to(_pad_buttons[left_index])
		button.focus_neighbor_right = button.get_path_to(_pad_buttons[right_index])
		button.focus_neighbor_top = button.get_path_to(
			_pad_cancel if up_index < 0 else _pad_buttons[up_index]
		)
		if down_index >= _pad_buttons.size():
			button.focus_neighbor_bottom = button.get_path_to(_pad_confirm)
		else:
			button.focus_neighbor_bottom = button.get_path_to(_pad_buttons[down_index])
	_pad_confirm.focus_neighbor_top = _pad_confirm.get_path_to(_pad_buttons[10])
	_pad_confirm.focus_neighbor_bottom = _pad_confirm.get_path_to(_pad_cancel)
	_pad_confirm.focus_neighbor_left = _pad_confirm.get_path_to(_pad_confirm)
	_pad_confirm.focus_neighbor_right = _pad_confirm.get_path_to(_pad_confirm)
	_pad_cancel.focus_neighbor_top = _pad_cancel.get_path_to(_pad_cancel)
	_pad_cancel.focus_neighbor_bottom = _pad_cancel.get_path_to(_pad_buttons[0])
	_pad_cancel.focus_neighbor_left = _pad_cancel.get_path_to(_pad_cancel)
	_pad_cancel.focus_neighbor_right = _pad_cancel.get_path_to(_pad_cancel)

func _link_vertical(controls: Array[Control]) -> void:
	for index: int in controls.size():
		var previous: Control = controls[posmod(index - 1, controls.size())]
		var next: Control = controls[(index + 1) % controls.size()]
		controls[index].focus_neighbor_top = controls[index].get_path_to(previous)
		controls[index].focus_neighbor_bottom = controls[index].get_path_to(next)
