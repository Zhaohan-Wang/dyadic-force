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

## 设置弹窗根节点（含遮罩）
var _settings_layer: Control = null
## 打开设置前聚焦的按钮（关闭时还原焦点）
var _settings_return_focus: Control = null

func _ready() -> void:
	_build()

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

	# 副标题：比 LOGO 小两档，只交代题材，不抢招牌
	var sub: Label = MenuKit.make_world_caption("TWO MONKEYS - ONE BIG BALL", 22)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-400, 448)
	sub.size = Vector2(800, 40)
	add_child(sub)
	UiSpring.attach(sub, 0.55, 0.25).pop_in(0.15)

	# ---- 菜单按钮：左下角（背景棋盘垫区域），避开中部猴子推球主体 ----
	var col: VBoxContainer = VBoxContainer.new()
	col.position = Vector2(120, 590)
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
	hint.add_child(MenuKit.make_world_caption("MOVE", 22))
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(36, 0)
	hint.add_child(spacer)
	hint.add_child(MenuKit.make_pad_icon("a", 40.0))
	hint.add_child(MenuKit.make_world_caption("SELECT", 22))

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

	# 面板标题：强调橙 + 面板硬阴影（奶油底上绝不用奶油字）
	var title: Label = MenuKit.make_title_label("SETTINGS", 32, MenuKit.COL_ACCENT, true)
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

func _on_start() -> void:
	SceneDirector.go_to("res://scenes/pairing_screen.tscn")
