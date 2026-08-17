extends Control
## 校准后的四页图文教学。确认向后翻页，返回向前翻页。

const GUIDE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/ui/guides/guide_1.png"),
	preload("res://assets/ui/guides/guide_2.png"),
	preload("res://assets/ui/guides/guide_3.png"),
	preload("res://assets/ui/guides/guide_4.png"),
]

var _page: int = 0
var _image: TextureRect
var _page_label: Label
var _previous_button: Button
var _next_button: Button
var _dialog_spring: UiSpring
var _page_tween: Tween = null

func _ready() -> void:
	_build()
	InputHub.joy_hotplug.connect(_on_hotplug)
	_show_page(0, false)

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	var title: Control = MenuKit.make_pixel_outline_text(
		GameState.ui("游戏教学", "HOW TO PLAY"), 42, MenuKit.COL_CREAM, 3
	)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-420, 30)
	title.size = Vector2(840, 64)
	add_child(title)
	UiSpring.attach(title, 0.5, 0.3).pop_in(0.02)

	var dialog: NinePatchRect = MenuKit.make_dialog(Vector2(1360, 850))
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.position = Vector2(-680, -420)
	dialog.size = Vector2(1360, 850)
	add_child(dialog)
	_dialog_spring = UiSpring.attach(dialog, 0.5, 0.28)
	_dialog_spring.pop_in(0.08)

	var image_back: Panel = Panel.new()
	image_back.position = Vector2(38, 34)
	image_back.size = Vector2(1284, 704)
	image_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var image_style: StyleBoxFlat = StyleBoxFlat.new()
	image_style.bg_color = Color("30271f")
	image_style.border_color = MenuKit.COL_OUTLINE
	image_style.set_border_width_all(5)
	image_style.set_corner_radius_all(8)
	image_back.add_theme_stylebox_override("panel", image_style)
	dialog.add_child(image_back)

	_image = TextureRect.new()
	_image.position = Vector2(8, 8)
	_image.size = Vector2(1268, 688)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_back.add_child(_image)

	_previous_button = MenuKit.make_compact_button(
		GameState.ui("上一页", "PREVIOUS"), Vector2(250, 68)
	)
	_previous_button.position = Vector2(54, 758)
	# 键盘/手柄由页面统一处理按下边沿，按钮只响应鼠标，避免 Enter 松开时二次触发。
	_previous_button.focus_mode = Control.FOCUS_NONE
	_previous_button.pressed.connect(_previous_page)
	dialog.add_child(_previous_button)

	_next_button = MenuKit.make_compact_button(
		GameState.ui("下一页", "NEXT"), Vector2(250, 68)
	)
	_next_button.position = Vector2(1056, 758)
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.pressed.connect(_next_page)
	dialog.add_child(_next_button)

	_page_label = MenuKit.make_label("", 28, MenuKit.COL_INK, 0)
	_page_label.position = Vector2(505, 754)
	_page_label.size = Vector2(350, 36)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.add_child(_page_label)

	var hint: Control = MenuKit.make_pixel_outline_text(
		GameState.ui(
			"返回：上一页    ·    确认：下一页",
			"BACK: PREVIOUS    ·    CONFIRM: NEXT"
		),
		22,
		MenuKit.COL_CREAM,
		2,
	)
	hint.position = Vector2(380, 798)
	hint.size = Vector2(600, 32)
	dialog.add_child(hint)

func _show_page(index: int, animate: bool = true) -> void:
	_page = clampi(index, 0, GUIDE_TEXTURES.size() - 1)
	if _page_tween != null:
		_page_tween.kill()
	_image.texture = GUIDE_TEXTURES[_page]
	if animate:
		_image.modulate.a = 0.25
		_page_tween = create_tween()
		_page_tween.tween_property(_image, "modulate:a", 1.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_dialog_spring.punch(0.12)
	else:
		_image.modulate.a = 1.0

	MenuKit.set_label_text(
		_page_label,
		GameState.ui(
			"教学 %d / %d" % [_page + 1, GUIDE_TEXTURES.size()],
			"GUIDE %d / %d" % [_page + 1, GUIDE_TEXTURES.size()],
		),
	)
	_previous_button.disabled = _page == 0
	_next_button.text = GameState.ui("进入选关", "SELECT LEVEL") \
		if _page == GUIDE_TEXTURES.size() - 1 \
		else GameState.ui("下一页", "NEXT")

func _next_page() -> void:
	if _page >= GUIDE_TEXTURES.size() - 1:
		SceneDirector.go_to("res://scenes/level_select.tscn")
		return
	_show_page(_page + 1)

func _previous_page() -> void:
	if _page <= 0:
		return
	_show_page(_page - 1)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		if _page > 0:
			AudioHub.play_ui_click()
			_previous_page()
	elif event.is_action_pressed(InputHub.UI_ACCEPT_ACTION):
		get_viewport().set_input_as_handled()
		AudioHub.play_ui_click()
		_next_page()

func _on_hotplug(_device_id: int, _connected: bool) -> void:
	AudioHub.play_ui_error()
	SceneDirector.go_to("res://scenes/pairing_screen.tscn")
