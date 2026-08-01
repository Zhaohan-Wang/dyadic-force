extends Control
## 结算界面：星级逐颗弹出 + 用时 / 剩余生命，提供重试 / 选关 / 回标题。

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())
	add_child(MenuKit.make_dim_overlay(0.5))

	var result: Dictionary = GameState.last_result
	var success: bool = bool(result.get("success", false))
	var stars: int = int(result.get("stars", 0))

	var panel: NinePatchRect = MenuKit.make_panel(Vector2(680, 600))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-340, -310)
	panel.size = Vector2(680, 600)
	add_child(panel)
	UiSpring.attach(panel, 0.5, 0.3).pop_in(0.05)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48.0
	box.offset_right = -48.0
	box.offset_top = 44.0
	box.offset_bottom = -44.0
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)

	# ---- 标题与关名 ----
	var title: Label = MenuKit.make_label(
		"LEVEL CLEAR!" if success else "TIME'S UP!", 42,
		MenuKit.COL_ACCENT if success else MenuKit.COL_DANGER, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var name_label: Label = MenuKit.make_label(str(result.get("level_name", "")), 28, Color(MenuKit.COL_INK, 0.6), 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	# ---- 星级（逐颗弹出） ----
	var stars_row: HBoxContainer = HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 28)
	stars_row.custom_minimum_size = Vector2(0, 110)
	box.add_child(stars_row)
	for i: int in 3:
		var earned: bool = i < stars
		# 亮星用奶白（醒目），未获得用深色剪影压暗
		var star: TextureRect = MenuKit.make_icon("star_cream" if earned else "star_dark", 96.0)
		if not earned:
			star.self_modulate = Color(1, 1, 1, 0.3)
		stars_row.add_child(star)
		var spring: UiSpring = UiSpring.attach(star, 0.5, 0.4)
		spring.pop_in(0.35 + float(i) * 0.18, 0.2 if earned else 0.6)

	# ---- 数据行 ----
	var elapsed: float = float(result.get("elapsed", 0.0))
	var t: int = int(floor(elapsed))
	box.add_child(_make_stat_row("TIME", "%02d:%02d" % [t / 60, t % 60]))
	var hp: float = float(result.get("hp", 0.0))
	var max_hp: float = float(result.get("max_hp", 100.0))
	box.add_child(_make_stat_row("BALL HP", "%d / %d" % [int(round(hp)), int(round(max_hp))]))

	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)

	# ---- 按钮行 ----
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 20)
	box.add_child(actions)

	var retry: Button = MenuKit.make_big_button("RETRY", 28, Vector2(200, 96))
	retry.pressed.connect(_on_retry)
	actions.add_child(retry)

	var select: Button = MenuKit.make_big_button("LEVELS", 28, Vector2(200, 96))
	select.pressed.connect(func() -> void: SceneDirector.go_to("res://scenes/level_select.tscn"))
	actions.add_child(select)

	var title_btn: Button = MenuKit.make_big_button("TITLE", 28, Vector2(180, 96))
	title_btn.pressed.connect(func() -> void:
		InputHub.clear_slots()
		SceneDirector.go_to("res://scenes/title_screen.tscn")
	)
	actions.add_child(title_btn)

	retry.grab_focus.call_deferred()

## 一行结算数据：左名称右数值
func _make_stat_row(label_text: String, value_text: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label: Label = MenuKit.make_label(label_text, 28, Color(MenuKit.COL_INK, 0.6), 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label: Label = MenuKit.make_label(value_text, 28, MenuKit.COL_INK, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row

func _on_retry() -> void:
	if GameState.current_level != null:
		SceneDirector.go_to("res://scenes/level.tscn")
	else:
		SceneDirector.go_to("res://scenes/level_select.tscn")
