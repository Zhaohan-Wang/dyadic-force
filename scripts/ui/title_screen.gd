extends Control
## 标题画面：全屏像素场景背景 + LOGO 贴图（浮动动效）+ START/SETTINGS/QUIT。
## 背景图已含猴子推球场景，不再叠加代码猴子装饰。

## 全屏背景场景图（两只猴子推大球）
const TEX_BG: Texture2D = preload("res://assets/ui/title_bg.jpg")
## 抠好透明底的像素 LOGO（691x381，1:1 显示保证像素锐利）
const TEX_LOGO: Texture2D = preload("res://assets/ui/title_logo.png")
## LOGO 浮动动效的振幅（像素）与半周期（秒）
const LOGO_BOB_PX: float = 12.0
const LOGO_BOB_HALF_S: float = 1.6
## 手柄震动强度分档：关闭 / 轻柔 / 标准 / 强烈。
const HAPTIC_LEVELS: PackedFloat32Array = [0.0, 0.55, 0.85, 1.0]

## 设置弹窗根节点（含遮罩）
var _settings_layer: Control = null
## 打开设置前聚焦的按钮（关闭时还原焦点）
var _settings_return_focus: Control = null
## 底部动态输入提示容器，手柄热插拔时重建。
var _hint_holder: HBoxContainer

func _ready() -> void:
	_build()
	InputHub.joy_hotplug.connect(_on_joy_hotplug)

func _build() -> void:
	# ---- 全屏背景场景 ----
	var bg: TextureRect = TextureRect.new()
	bg.texture = TEX_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ---- LOGO 贴图：顶部居中，1:1 尺寸，上下缓慢浮动 ----
	var logo: TextureRect = TextureRect.new()
	logo.texture = TEX_LOGO
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var logo_y: float = 48.0
	logo.position = Vector2(-345.0, logo_y)
	logo.size = Vector2(691.0, 381.0)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	UiSpring.attach(logo, 0.55, 0.3).pop_in(0.05)
	# 浮动动效：正弦缓动上下往复（与弹簧只动 scale 不冲突）
	var bob: Tween = create_tween().set_loops()
	bob.tween_property(logo, "position:y", logo_y + LOGO_BOB_PX, LOGO_BOB_HALF_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(logo, "position:y", logo_y, LOGO_BOB_HALF_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 副标题使用独立粗体样式，避免通用标题描边吞掉中英文细笔画。
	var sub_text: String = GameState.ui("两只猴子 · 一颗大球", "TWO MONKEYS - ONE BIG BALL")
	var sub: Control = MenuKit.make_brand_subtitle(sub_text, 58)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-500, 430)
	sub.size = Vector2(1000, 68)
	add_child(sub)
	UiSpring.attach(sub, 0.55, 0.25).pop_in(0.15)

	# ---- 菜单：左下角棋盘区；模式开关在上，主按钮在下 ----
	var col: VBoxContainer = VBoxContainer.new()
	col.position = Vector2(120, 470)
	col.custom_minimum_size = Vector2(440, 560)
	col.add_theme_constant_override("separation", 16)
	add_child(col)

	# 模式滑动开关：默认关闭，勾选后写入 settings.cfg。
	col.add_child(_make_slide_switch_row(
		GameState.ui("实验模式", "EXPERIMENT MODE"),
		GameState.experiment_mode,
		func(on: bool) -> void:
			GameState.experiment_mode = on
			GameState.save_settings()
	))
	col.add_child(_make_slide_switch_row(
		GameState.ui("调试模式", "DEBUG MODE"),
		GameState.debug_mode,
		func(on: bool) -> void:
			GameState.debug_mode = on
			GameState.save_settings()
	))

	var start_btn: Button = MenuKit.make_big_button(
		GameState.ui("开始游戏", "START GAME"), 32, Vector2(440, 100)
	)
	start_btn.pressed.connect(_on_start)
	col.add_child(start_btn)

	var settings_btn: Button = MenuKit.make_big_button(
		GameState.ui("设置", "SETTINGS"), 32, Vector2(440, 100)
	)
	settings_btn.pressed.connect(_open_settings)
	col.add_child(settings_btn)

	var data_btn: Button = MenuKit.make_big_button(
		GameState.ui("打开数据文件夹", "OPEN DATA FOLDER"), 26, Vector2(440, 84)
	)
	data_btn.pressed.connect(_open_experiment_logs)
	col.add_child(data_btn)

	var quit_btn: Button = MenuKit.make_big_button(
		GameState.ui("退出游戏", "QUIT"), 32, Vector2(440, 100)
	)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(quit_btn)

	# 逐个弹入 + 初始焦点
	var delay: float = 0.25
	for child: Node in col.get_children():
		UiSpring.attach(child as Control, 0.5, 0.3).pop_in(delay)
		delay += 0.08
	start_btn.grab_focus.call_deferred()

	# ---- 底部操作提示 ----
	_hint_holder = HBoxContainer.new()
	_hint_holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_holder.position = Vector2(-480, -82)
	_hint_holder.custom_minimum_size = Vector2(960, 54)
	_hint_holder.add_theme_constant_override("separation", 28)
	_hint_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_hint_holder)
	_refresh_input_hints()

## 根据当前检测到的设备组合刷新标题页提示。
func _refresh_input_hints() -> void:
	for child: Node in _hint_holder.get_children():
		child.queue_free()
	var profile: InputHub.SessionProfile = InputHub.menu_profile()
	_hint_holder.add_child(MenuKit.make_device_hint_row(
		["UP", "DOWN"], ["dpad"], GameState.ui("移动", "MOVE"), 40.0, profile
	))
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(36, 0)
	_hint_holder.add_child(spacer)
	_hint_holder.add_child(MenuKit.make_device_hint_row(
		["ENTER"], ["a"], GameState.ui("确认", "SELECT"), 40.0, profile
	))

# ---------- 设置弹窗 ----------

func _open_settings() -> void:
	if _settings_layer != null:
		return
	_settings_return_focus = get_viewport().gui_get_focus_owner()

	_settings_layer = MenuKit.full_rect_root()
	add_child(_settings_layer)
	_settings_layer.add_child(MenuKit.make_dim_overlay())

	var panel: NinePatchRect = MenuKit.make_panel(Vector2(620, 760))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310, -380)
	panel.size = Vector2(620, 760)
	_settings_layer.add_child(panel)
	UiSpring.attach(panel, 0.45, 0.3).pop_in(0.0)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48.0
	box.offset_right = -48.0
	box.offset_top = 40.0
	box.offset_bottom = -40.0
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	# 面板标题：强调橙 + 面板硬阴影（奶油底上绝不用奶油字）
	var title: Label = MenuKit.make_title_label(
		GameState.ui("设置", "SETTINGS"), 36, MenuKit.COL_ACCENT, true
	)
	box.add_child(title)

	var language_row: Control = _make_language_row()
	box.add_child(language_row)

	var shake_row: Control = _make_toggle_row(GameState.ui("画面震动", "SCREEN SHAKE"), GameState.shake_enabled,
		func(on: bool) -> void:
			GameState.shake_enabled = on
			GameState.save_settings()
	)
	box.add_child(shake_row)

	var vignette_row: Control = _make_toggle_row(GameState.ui("暗角效果", "VIGNETTE"), GameState.vignette_enabled,
		func(on: bool) -> void:
			GameState.vignette_enabled = on
			GameState.save_settings()
	)
	box.add_child(vignette_row)

	var haptic_row: Control = _make_haptic_row()
	box.add_child(haptic_row)

	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)

	var done: Button = MenuKit.make_big_button(
		GameState.ui("完成", "DONE"), 30, Vector2(280, 96)
	)
	done.pressed.connect(_close_settings)
	var done_holder: HBoxContainer = HBoxContainer.new()
	done_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	done_holder.add_child(done)
	box.add_child(done_holder)

	# 焦点移进弹窗
	var language_button: Button = language_row.get_node("Language") as Button
	language_button.grab_focus.call_deferred()

## 语言设置行：显示当前语言，按下后立即切换并重建标题页。
func _make_language_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 82)
	var label: Label = MenuKit.make_label(
		GameState.ui("语言", "LANGUAGE"), 30, MenuKit.COL_INK, 0
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var language_button: Button = MenuKit.make_big_button(
		"中文" if GameState.language == GameState.LANGUAGE_ZH else "ENGLISH",
		26,
		Vector2(250, 76),
	)
	language_button.name = "Language"
	language_button.pressed.connect(_toggle_language)
	row.add_child(language_button)
	return row

func _toggle_language() -> void:
	var next: String = (
		GameState.LANGUAGE_EN
		if GameState.language == GameState.LANGUAGE_ZH
		else GameState.LANGUAGE_ZH
	)
	GameState.set_language(next)
	_rebuild_for_language.call_deferred()

## 手柄震动强度：提供关闭与三档强度，兼顾可访问性和不同硬件差异。
func _make_haptic_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 82)
	var label: Label = MenuKit.make_label(
		GameState.ui("手柄震动", "CONTROLLER VIBRATION"), 28, MenuKit.COL_INK, 0
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var button: Button = MenuKit.make_big_button(
		_haptic_level_text(), 24, Vector2(250, 76)
	)
	button.name = "Haptics"
	button.pressed.connect(func() -> void:
		_cycle_haptic_strength()
		button.text = _haptic_level_text()
		HapticHub.preview_connected()
	)
	row.add_child(button)
	return row

func _cycle_haptic_strength() -> void:
	var nearest_index: int = 0
	var nearest_distance: float = INF
	for index: int in HAPTIC_LEVELS.size():
		var distance: float = absf(GameState.haptic_strength - HAPTIC_LEVELS[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	var next_index: int = (nearest_index + 1) % HAPTIC_LEVELS.size()
	GameState.haptic_strength = HAPTIC_LEVELS[next_index]
	GameState.save_settings()

func _haptic_level_text() -> String:
	if GameState.haptic_strength < 0.1:
		return GameState.ui("关闭", "OFF")
	if GameState.haptic_strength < 0.7:
		return GameState.ui("轻柔", "GENTLE")
	if GameState.haptic_strength < 0.95:
		return GameState.ui("标准", "STANDARD")
	return GameState.ui("强烈", "STRONG")

## 切换语言后重建代码生成的界面，保证所有文本和字体立即更新。
func _rebuild_for_language() -> void:
	_settings_layer = null
	_settings_return_focus = null
	for child: Node in get_children():
		child.free()
	_build()

## 标题页模式开关：像素描边大字 + 与圆同高的胶囊槽。
func _make_slide_switch_row(text: String, initial: bool, on_changed: Callable) -> Control:
	# 圆直径决定槽高；角半径 = 半高，两端才是真正的半圆胶囊。
	const KNOB: float = 36.0
	const TRACK_H: float = KNOB
	const TRACK_W: float = 84.0
	const KNOB_ON_X: float = TRACK_W - KNOB
	const KNOB_OFF_X: float = 0.0
	const CAPSULE_RADIUS: int = int(TRACK_H * 0.5)

	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 64)
	row.add_theme_constant_override("separation", 20)
	# 不用 Label 自带 outline（中文像素字会发脏），改用方形核扩张描边。
	var label: Control = MenuKit.make_pixel_outline_text(text, 32, MenuKit.COL_CREAM, 2)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var switch_btn: Button = Button.new()
	switch_btn.toggle_mode = true
	switch_btn.button_pressed = initial
	switch_btn.custom_minimum_size = Vector2(TRACK_W, TRACK_H)
	switch_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	switch_btn.focus_mode = Control.FOCUS_ALL
	switch_btn.flat = true
	switch_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var empty := StyleBoxEmpty.new()
		switch_btn.add_theme_stylebox_override(state, empty)

	var track: Panel = Panel.new()
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_off := StyleBoxFlat.new()
	track_off.bg_color = Color("3a2a1c")
	track_off.corner_radius_top_left = CAPSULE_RADIUS
	track_off.corner_radius_top_right = CAPSULE_RADIUS
	track_off.corner_radius_bottom_left = CAPSULE_RADIUS
	track_off.corner_radius_bottom_right = CAPSULE_RADIUS
	track_off.border_width_left = 2
	track_off.border_width_top = 2
	track_off.border_width_right = 2
	track_off.border_width_bottom = 2
	track_off.border_color = Color("2a1c12")
	var track_on := track_off.duplicate() as StyleBoxFlat
	track_on.bg_color = MenuKit.COL_READY
	track_on.border_color = Color("3f6e28")
	track.add_theme_stylebox_override("panel", track_on if initial else track_off)
	switch_btn.add_child(track)

	var knob: Panel = Panel.new()
	knob.custom_minimum_size = Vector2(KNOB, KNOB)
	knob.size = Vector2(KNOB, KNOB)
	knob.position = Vector2(KNOB_ON_X if initial else KNOB_OFF_X, 0.0)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = MenuKit.COL_CREAM
	knob_style.corner_radius_top_left = CAPSULE_RADIUS
	knob_style.corner_radius_top_right = CAPSULE_RADIUS
	knob_style.corner_radius_bottom_left = CAPSULE_RADIUS
	knob_style.corner_radius_bottom_right = CAPSULE_RADIUS
	knob_style.border_width_left = 2
	knob_style.border_width_top = 2
	knob_style.border_width_right = 2
	knob_style.border_width_bottom = 2
	knob_style.border_color = MenuKit.COL_OUTLINE
	knob.add_theme_stylebox_override("panel", knob_style)
	switch_btn.add_child(knob)

	var spring: UiSpring = UiSpring.attach(switch_btn, 0.4, 0.35)
	switch_btn.focus_entered.connect(func() -> void: spring.set_scale_target(1.08))
	switch_btn.focus_exited.connect(func() -> void: spring.set_scale_target(1.0))
	switch_btn.mouse_entered.connect(func() -> void: switch_btn.grab_focus())
	switch_btn.toggled.connect(func(on: bool) -> void:
		track.add_theme_stylebox_override("panel", track_on if on else track_off)
		var tween: Tween = switch_btn.create_tween()
		tween.tween_property(knob, "position:x", KNOB_ON_X if on else KNOB_OFF_X, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		spring.punch(0.22)
		on_changed.call(on)
	)
	row.add_child(switch_btn)
	return row

## 一行设置项：左侧文字，右侧 Sprout 勾选块
func _make_toggle_row(text: String, initial: bool, on_changed: Callable) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 72)
	var label: Label = MenuKit.make_label(text, 28, MenuKit.COL_INK, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var toggle: Button = Button.new()
	toggle.name = "Toggle"
	toggle.toggle_mode = true
	toggle.button_pressed = initial
	toggle.custom_minimum_size = Vector2(72, 72)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var square: StyleBoxTexture = MenuKit.make_square_stylebox()
	toggle.add_theme_stylebox_override("normal", square)
	toggle.add_theme_stylebox_override("hover", square)
	toggle.add_theme_stylebox_override("focus", square)
	toggle.add_theme_stylebox_override("pressed", square)

	var check: TextureRect = MenuKit.make_icon("check_dark", 44.0)
	check.set_anchors_preset(Control.PRESET_CENTER)
	check.position = Vector2(-22, -24)
	check.visible = initial
	toggle.add_child(check)

	var spring: UiSpring = UiSpring.attach(toggle, 0.4, 0.35)
	toggle.focus_entered.connect(func() -> void: spring.set_scale_target(1.1))
	toggle.focus_exited.connect(func() -> void: spring.set_scale_target(1.0))
	toggle.mouse_entered.connect(func() -> void: toggle.grab_focus())
	toggle.toggled.connect(func(on: bool) -> void:
		check.visible = on
		spring.punch(0.3)
		on_changed.call(on)
	)
	row.add_child(toggle)
	return row

func _close_settings() -> void:
	if _settings_layer == null:
		return
	_settings_layer.queue_free()
	_settings_layer = null
	if _settings_return_focus != null and is_instance_valid(_settings_return_focus):
		_settings_return_focus.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if _settings_layer != null:
			_close_settings()
			get_viewport().set_input_as_handled()

## 在 UI 控件处理前响应取消键，确保 Xbox B / Nintendo B 能可靠关闭设置。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION) and _settings_layer != null:
		_close_settings()
		get_viewport().set_input_as_handled()

func _on_start() -> void:
	if not GameState.experiment_mode:
		# 非实验模式跳过编号/组别录入，也不应带着上次锁定的实验元数据。
		GameState.experiment_setup_locked = false
	SceneDirector.go_to(GameState.start_flow_scene())

## 一键打开实验数据根目录；目录不存在时先创建再打开。
func _open_experiment_logs() -> void:
	var log_dir: String = ExperimentLog.ensure_root()
	if log_dir.is_empty() or not DirAccess.dir_exists_absolute(log_dir):
		push_warning("TitleScreen: cannot create experiments directory")
		return
	var error: Error = OS.shell_open(ProjectSettings.globalize_path(log_dir))
	if error != OK:
		push_warning("TitleScreen: failed to open experiments directory (%s)" % error)

func _on_joy_hotplug(_device_id: int, _connected: bool) -> void:
	if _hint_holder != null and is_instance_valid(_hint_holder):
		_refresh_input_hints()
