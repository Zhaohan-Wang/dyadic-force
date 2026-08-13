class_name PhysicsDebugPanel
extends CanvasLayer
## 教学关局内物理调试条：贴在屏幕左侧，拖动后立即套到球上。

var _ball: PixelBall
var _slider_by_key: Dictionary = {}
var _value_label_by_key: Dictionary = {}
var _status_label: Label

func setup(ball: PixelBall) -> void:
	_ball = ball
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	PhysicsTuning.ensure_loaded()
	_build()

func _build() -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel: NinePatchRect = MenuKit.make_panel(Vector2(360, 700))
	panel.position = Vector2(24, 190)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 22
	box.offset_right = -22
	box.offset_top = 18
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(box)

	box.add_child(MenuKit.make_title_label(
		GameState.ui("物理调试", "PHYSICS"), 24, MenuKit.COL_ACCENT, true
	))

	for spec: Dictionary in PhysicsTuning.SPECS:
		box.add_child(_make_param_slider(spec))

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)

	var reset_btn: Button = MenuKit.make_compact_button(
		GameState.ui("重置", "RESET"), Vector2(140, 52)
	)
	reset_btn.pressed.connect(_on_reset)
	actions.add_child(reset_btn)

	var save_btn: Button = MenuKit.make_compact_button(
		GameState.ui("保存", "SAVE"), Vector2(140, 52)
	)
	save_btn.pressed.connect(_on_save)
	actions.add_child(save_btn)

	_status_label = MenuKit.make_panel_label("", 16, 0.7)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status_label)

func _make_param_slider(spec: Dictionary) -> Control:
	var key: String = str(spec["key"])
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size = Vector2(0, 48)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	row.add_child(header)

	var name_label: Label = MenuKit.make_panel_label(
		GameState.ui(str(spec["zh"]), str(spec["en"])), 18
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var value_label: Label = MenuKit.make_panel_label(
		PhysicsTuning.format_value(key, PhysicsTuning.get_value(key)), 18
	)
	value_label.custom_minimum_size = Vector2(72, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_label)
	_value_label_by_key[key] = value_label

	var slider: HSlider = HSlider.new()
	slider.min_value = float(spec["min"])
	slider.max_value = float(spec["max"])
	slider.step = float(spec["step"])
	slider.value = PhysicsTuning.get_value(key)
	slider.custom_minimum_size = Vector2(300, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	_style_slider(slider)
	slider.value_changed.connect(func(v: float) -> void:
		PhysicsTuning.set_value(key, v)
		value_label.text = PhysicsTuning.format_value(key, PhysicsTuning.get_value(key))
		PhysicsTuning.apply_to_ball(_ball)
		if _status_label != null:
			_status_label.text = ""
	)
	row.add_child(slider)
	_slider_by_key[key] = slider
	return row

func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(MenuKit.COL_INK, 0.18)
	track.corner_radius_top_left = 6
	track.corner_radius_top_right = 6
	track.corner_radius_bottom_left = 6
	track.corner_radius_bottom_right = 6
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.COL_ACCENT
	fill.corner_radius_top_left = 6
	fill.corner_radius_top_right = 6
	fill.corner_radius_bottom_left = 6
	fill.corner_radius_bottom_right = 6
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)

func _refresh_sliders_from_values() -> void:
	for key: Variant in _slider_by_key.keys():
		var key_name: String = str(key)
		var slider: HSlider = _slider_by_key[key_name] as HSlider
		var value_label: Label = _value_label_by_key.get(key_name) as Label
		if slider == null:
			continue
		var value: float = PhysicsTuning.get_value(key_name)
		slider.set_value_no_signal(value)
		if value_label != null:
			value_label.text = PhysicsTuning.format_value(key_name, value)

func _on_reset() -> void:
	PhysicsTuning.reset_to_defaults()
	_refresh_sliders_from_values()
	PhysicsTuning.apply_to_ball(_ball)
	if _status_label != null:
		_status_label.text = GameState.ui("已恢复默认", "DEFAULTS RESTORED")

func _on_save() -> void:
	if PhysicsTuning.save_to_disk():
		if _status_label != null:
			_status_label.text = GameState.ui("已保存到本地文件", "SAVED TO LOCAL FILE")
	elif _status_label != null:
		_status_label.text = GameState.ui("保存失败", "SAVE FAILED")
