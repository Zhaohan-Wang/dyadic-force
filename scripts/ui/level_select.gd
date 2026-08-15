extends Control
## 选关界面：练习关 + 正式关。
## 每关一张大按钮卡：左侧关名，右侧限时信息与通关星标。
## 实验协议由录入页锁定；本页只读展示组号与协议版本。

var _condition_value: Control

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	# 页面标题统一用街机粗方块字（Press Start 2P）
	var title: Control = MenuKit.make_pixel_outline_text(
		GameState.ui("选择关卡", "SELECT LEVEL"), 40, MenuKit.COL_CREAM, 3
	)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 40)
	title.size = Vector2(800, 72)
	add_child(title)
	UiSpring.attach(title, 0.5, 0.3).pop_in(0.02)

	var list_top: float = 140.0
	if GameState.experiment_mode:
		# 标准协议在配对前锁定，本页不提供条件切换入口。
		var cond_row: HBoxContainer = HBoxContainer.new()
		cond_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
		cond_row.position = Vector2(-420, 118)
		cond_row.custom_minimum_size = Vector2(840, 48)
		cond_row.add_theme_constant_override("separation", 28)
		cond_row.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(cond_row)
		var cond_label: Control = MenuKit.make_world_caption(
			GameState.ui("实验协议（已锁定）", "PROTOCOL (LOCKED)"), 24
		)
		cond_row.add_child(cond_label)
		_condition_value = MenuKit.make_world_caption(_protocol_text(), 28)
		MenuKit.set_pixel_outline_color(_condition_value, MenuKit.COL_ACCENT)
		cond_row.add_child(_condition_value)
		list_top = 180.0

	# 正式关加到 5 关后，列表用滚动容器避免超出一屏。
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER_TOP)
	scroll.position = Vector2(-380, list_top)
	scroll.custom_minimum_size = Vector2(760, 820.0 - list_top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(740, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	scroll.add_child(col)

	var delay: float = 0.12
	var level_buttons: Array[Button] = []
	for path: String in GameState.LEVEL_ORDER:
		var def: LevelDef = load(path) as LevelDef
		if def == null:
			continue
		var btn: Button = _make_level_button(def)
		col.add_child(btn)
		level_buttons.append(btn)
		UiSpring.attach(btn, 0.5, 0.3).pop_in(delay)
		delay += 0.07
	for index: int in level_buttons.size():
		var previous: Button = level_buttons[posmod(index - 1, level_buttons.size())]
		var next: Button = level_buttons[(index + 1) % level_buttons.size()]
		level_buttons[index].focus_neighbor_top = level_buttons[index].get_path_to(previous)
		level_buttons[index].focus_neighbor_bottom = level_buttons[index].get_path_to(next)
	if not level_buttons.is_empty():
		level_buttons[0].grab_focus.call_deferred()

	# 左上角返回提示
	var back_row: HBoxContainer = MenuKit.make_device_hint_row(
		["ESC"],
		["b"],
		GameState.ui("返回", "BACK"),
		44.0,
		InputHub.session_profile(),
	)
	back_row.position = Vector2(40, 36)
	add_child(back_row)

func _protocol_text() -> String:
	var dyad: String = GameState.dyad_id if not GameState.dyad_id.is_empty() else "—"
	return "%s · %s" % [GameState.protocol_version, dyad]

## 关卡卡片按钮：名称 + 限时/无计时 + 通关星
func _make_level_button(def: LevelDef) -> Button:
	var btn: Button = MenuKit.make_big_button("", 28, Vector2(720, 108))
	btn.pressed.connect(func() -> void: _start_level(def))

	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 40.0
	row.offset_right = -40.0
	row.offset_top = 8.0
	row.offset_bottom = -18.0
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var name_label: Label = MenuKit.make_label(
		GameState.localize_content(def.level_name), 30, MenuKit.COL_INK, 0
	)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var info_text: String = (
		GameState.ui("不限时", "NO TIMER")
		if def.is_practice
		else GameState.ui("%d 秒" % int(def.time_limit), "%d SEC" % int(def.time_limit))
	)
	var info_label: Label = MenuKit.make_label(info_text, 28, Color(MenuKit.COL_INK, 0.55), 0)
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info_label)

	if GameState.is_cleared(def.level_id):
		row.add_child(MenuKit.make_icon("star_dark", 44.0))

	# 焦点时文字跟随高亮（大按钮本体只管背景与弹簧）
	btn.focus_entered.connect(func() -> void: name_label.label_settings.font_color = MenuKit.COL_ACCENT)
	btn.focus_exited.connect(func() -> void: name_label.label_settings.font_color = MenuKit.COL_INK)
	return btn

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		SceneDirector.go_to("res://scenes/pairing_screen.tscn")

## 在 UI 控件处理前响应取消键，确保 Xbox B / Nintendo B 能可靠返回配对页。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		SceneDirector.go_to("res://scenes/pairing_screen.tscn")

func _start_level(def: LevelDef) -> void:
	GameState.current_level = def
	SceneDirector.go_to("res://scenes/level.tscn")
