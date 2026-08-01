extends Control
## 标题画面：LOGO + 猴子装饰 + START/SETTINGS/QUIT。
## 全部构件走 MenuKit（Sprout 素材），入场用弹簧逐个弹入。

## 设置弹窗根节点（含遮罩）
var _settings_layer: Control = null
## 打开设置前聚焦的按钮（关闭时还原焦点）
var _settings_return_focus: Control = null

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	# ---- LOGO ----
	var logo: Label = MenuKit.make_label("DYADIC FORCE", 84)
	logo.label_settings.shadow_color = Color(MenuKit.COL_OUTLINE, 0.55)
	logo.label_settings.shadow_offset = Vector2(0, 8)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.position = Vector2(-600, 150)
	logo.size = Vector2(1200, 100)
	add_child(logo)
	UiSpring.attach(logo, 0.55, 0.3).pop_in(0.05)

	var sub: Label = MenuKit.make_label("TWO MONKEYS - ONE BIG BALL", 28, Color(1.0, 0.93, 0.78, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-400, 268)
	sub.size = Vector2(800, 40)
	add_child(sub)
	UiSpring.attach(sub, 0.55, 0.25).pop_in(0.15)

	# ---- 菜单按钮 ----
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.position = Vector2(-220, 420)
	col.custom_minimum_size = Vector2(440, 400)
	col.add_theme_constant_override("separation", 28)
	add_child(col)

	var start_btn: Button = MenuKit.make_big_button("START GAME", 28, Vector2(440, 108))
	start_btn.pressed.connect(_on_start)
	col.add_child(start_btn)

	var settings_btn: Button = MenuKit.make_big_button("SETTINGS", 28, Vector2(440, 108))
	settings_btn.pressed.connect(_open_settings)
	col.add_child(settings_btn)

	var quit_btn: Button = MenuKit.make_big_button("QUIT", 28, Vector2(440, 108))
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(quit_btn)

	# 逐个弹入 + 初始焦点
	var delay: float = 0.25
	for child: Node in col.get_children():
		var btn: Button = child as Button
		UiSpring.attach(btn, 0.5, 0.3).pop_in(delay)
		delay += 0.08
	start_btn.grab_focus.call_deferred()

	# ---- 两侧猴子装饰 ----
	_add_monkey(Vector2(560, 700), false, 0.4)
	_add_monkey(Vector2(1360, 700), true, 0.5)

	# ---- 底部操作提示 ----
	var hint: HBoxContainer = HBoxContainer.new()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-330, -76)
	hint.custom_minimum_size = Vector2(660, 48)
	hint.add_theme_constant_override("separation", 14)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hint)
	hint.add_child(MenuKit.make_key_icon("UP", 40.0))
	hint.add_child(MenuKit.make_key_icon("DOWN", 40.0))
	hint.add_child(MenuKit.make_label("MOVE", 28, Color(1, 1, 1, 0.75)))
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(36, 0)
	hint.add_child(spacer)
	hint.add_child(MenuKit.make_pad_icon("a", 40.0))
	hint.add_child(MenuKit.make_label("SELECT", 28, Color(1, 1, 1, 0.75)))

## 摆一只闲置动画的猴子并渐入
func _add_monkey(pos: Vector2, flip: bool, delay: float) -> void:
	var holder: Control = Control.new()
	holder.position = pos
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var monkey: AnimatedSprite2D = MenuKit.make_monkey_sprite(6.0, flip)
	holder.add_child(monkey)
	holder.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_interval(delay)
	tween.tween_property(holder, "modulate:a", 1.0, 0.3)

# ---------- 设置弹窗 ----------

func _open_settings() -> void:
	if _settings_layer != null:
		return
	_settings_return_focus = get_viewport().gui_get_focus_owner()

	_settings_layer = MenuKit.full_rect_root()
	add_child(_settings_layer)
	_settings_layer.add_child(MenuKit.make_dim_overlay())

	var panel: NinePatchRect = MenuKit.make_panel(Vector2(560, 520))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-280, -260)
	panel.size = Vector2(560, 520)
	_settings_layer.add_child(panel)
	UiSpring.attach(panel, 0.45, 0.3).pop_in(0.0)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48.0
	box.offset_right = -48.0
	box.offset_top = 40.0
	box.offset_bottom = -40.0
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)

	var title: Label = MenuKit.make_label("SETTINGS", 42, MenuKit.COL_INK, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var shake_row: Control = _make_toggle_row("SCREEN SHAKE", GameState.shake_enabled,
		func(on: bool) -> void:
			GameState.shake_enabled = on
			GameState.save_settings()
	)
	box.add_child(shake_row)

	var vignette_row: Control = _make_toggle_row("VIGNETTE", GameState.vignette_enabled,
		func(on: bool) -> void:
			GameState.vignette_enabled = on
			GameState.save_settings()
	)
	box.add_child(vignette_row)

	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)

	var done: Button = MenuKit.make_big_button("DONE", 28, Vector2(280, 96))
	done.pressed.connect(_close_settings)
	var done_holder: HBoxContainer = HBoxContainer.new()
	done_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	done_holder.add_child(done)
	box.add_child(done_holder)

	# 焦点移进弹窗
	var first_toggle: Button = shake_row.get_node("Toggle") as Button
	first_toggle.grab_focus.call_deferred()

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
	var normal: StyleBoxTexture = StyleBoxTexture.new()
	normal.texture = load("res://assets/ui/sprout_btn_square.png") as Texture2D
	normal.region_rect = Rect2(11, 59, 26, 28)
	normal.texture_margin_left = 8.0
	normal.texture_margin_right = 8.0
	normal.texture_margin_top = 8.0
	normal.texture_margin_bottom = 10.0
	toggle.add_theme_stylebox_override("normal", normal)
	toggle.add_theme_stylebox_override("hover", normal)
	toggle.add_theme_stylebox_override("focus", normal)
	toggle.add_theme_stylebox_override("pressed", normal)

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

func _on_start() -> void:
	SceneDirector.go_to("res://scenes/pairing_screen.tscn")
