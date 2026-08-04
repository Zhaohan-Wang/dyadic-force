class_name PauseMenu
extends CanvasLayer
## 关卡内暂停菜单：继续 / 重开本关 / 返回选关。
## process_mode = ALWAYS，以便在 get_tree().paused 时仍可操作。

signal resume_requested
signal restart_requested
signal level_select_requested

var _open: bool = false
var _panel: NinePatchRect
var _resume_btn: Button

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func is_open() -> bool:
	return _open

func open_menu() -> void:
	if _open:
		return
	_open = true
	visible = true
	if _panel != null:
		UiSpring.attach(_panel, 0.45, 0.3).pop_in(0.0)
	if _resume_btn != null:
		_resume_btn.grab_focus.call_deferred()

func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false

func _build() -> void:
	add_child(MenuKit.make_dim_overlay(0.55))

	var panel_size: Vector2 = Vector2(560, 520)
	_panel = MenuKit.make_panel(panel_size)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = -panel_size * 0.5
	_panel.size = panel_size
	add_child(_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48.0
	box.offset_right = -48.0
	box.offset_top = 44.0
	box.offset_bottom = -44.0
	box.add_theme_constant_override("separation", 22)
	_panel.add_child(box)

	var title: Label = MenuKit.make_title_label(
		GameState.ui("暂停", "PAUSED"), 40, MenuKit.COL_ACCENT, true
	)
	box.add_child(title)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)

	_resume_btn = _add_menu_button(box, GameState.ui("继续游戏", "RESUME"), func() -> void:
		resume_requested.emit()
	)
	_add_menu_button(box, GameState.ui("重新开始本关", "RESTART LEVEL"), func() -> void:
		restart_requested.emit()
	)
	_add_menu_button(box, GameState.ui("返回选关", "LEVEL SELECT"), func() -> void:
		level_select_requested.emit()
	)

	var hint: Label = MenuKit.make_panel_label(
		GameState.ui("ESC / 菜单键 关闭", "ESC / MENU TO CLOSE"), 22, 0.55
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

func _add_menu_button(parent: Node, text: String, on_pressed: Callable) -> Button:
	var holder: HBoxContainer = HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn: Button = MenuKit.make_big_button(text, 28, Vector2(420, 92))
	btn.pressed.connect(on_pressed)
	holder.add_child(btn)
	parent.add_child(holder)
	return btn

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if InputHub.is_pause_toggle_event(event):
		get_viewport().set_input_as_handled()
		resume_requested.emit()
		return
	# B / 取消也可继续，与常见暂停菜单一致
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		resume_requested.emit()
