class_name ShortIdInput
extends VBoxContainer
## 去标识化数字编号栏：只负责显示与校验，虚拟键盘由录入页共用。

signal value_changed(value: String)
signal editing_changed(editing: bool)

var value: String = ""
var editing: bool = false
var _caption: String = ""
var _display_button: Button

func setup(caption: String, initial_value: String = "") -> void:
	_caption = caption
	value = GameState.sanitize_experiment_id(initial_value)
	_build()

func _build() -> void:
	add_theme_constant_override("separation", 6)
	var caption_label: Label = MenuKit.make_panel_label(_caption, 22)
	add_child(caption_label)

	_display_button = MenuKit.make_big_button("", 26, Vector2(520, 64))
	_display_button.name = "Edit"
	_display_button.pressed.connect(begin_editing)
	add_child(_display_button)
	_refresh()

func set_value(next_value: String) -> void:
	var clean: String = GameState.sanitize_experiment_id(next_value)
	if clean == value:
		return
	value = clean
	_refresh()
	value_changed.emit(value)

func append_digit(digit: String) -> void:
	if value.length() >= GameState.ID_MAX_LENGTH:
		return
	if digit.length() == 1 and digit >= "0" and digit <= "9":
		set_value(value + digit)

func backspace() -> void:
	if value.is_empty():
		return
	set_value(value.left(value.length() - 1))

func clear_value() -> void:
	set_value("")

func begin_editing() -> void:
	if editing:
		return
	editing = true
	_refresh()
	editing_changed.emit(true)

func finish_editing() -> void:
	if not editing:
		return
	editing = false
	_refresh()
	_display_button.grab_focus.call_deferred()
	editing_changed.emit(false)

func focus_entry() -> void:
	_display_button.grab_focus.call_deferred()

func entry_button() -> Button:
	return _display_button

func _refresh() -> void:
	if _display_button == null:
		return
	if editing and not value.is_empty():
		_display_button.text = "%s  _" % value
	elif editing:
		_display_button.text = GameState.ui("输入数字…  _", "ENTER DIGITS...  _")
	elif not value.is_empty():
		_display_button.text = value
	else:
		_display_button.text = GameState.ui("回车 / A / 点击编辑", "ENTER / A / CLICK TO EDIT")

func _input(event: InputEvent) -> void:
	if not editing:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
			backspace()
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_ESCAPE:
			finish_editing()
			get_viewport().set_input_as_handled()
			return
		if key.unicode > 0:
			var typed: String = String.chr(key.unicode)
			if typed >= "0" and typed <= "9":
				append_digit(typed)
				get_viewport().set_input_as_handled()
				return

	var joy: InputEventJoypadButton = event as InputEventJoypadButton
	if joy != null and joy.pressed:
		if joy.button_index == JOY_BUTTON_X:
			clear_value()
			get_viewport().set_input_as_handled()
		elif joy.button_index == JOY_BUTTON_START:
			finish_editing()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		backspace()
		get_viewport().set_input_as_handled()
