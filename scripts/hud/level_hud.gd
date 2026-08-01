class_name LevelHud
extends CanvasLayer
## 关卡 HUD：红心血量、计时面板、教程对话气泡、开场关名提示。
## 只订阅 LevelState 信号，不直接接触关卡逻辑。

## 每颗红心代表的 HP 值
const HP_PER_HEART: float = 20.0
## 红心数量
const HEART_COUNT: int = 5

var _state: LevelState
var _root: Control
## 红心节点与其弹簧
var _hearts: Array[TextureRect] = []
var _heart_springs: Array[UiSpring] = []
## 上一次显示的半心数量（用于判断掉血弹动哪颗心）
var _prev_halves: int = -1
var _time_label: Label
var _time_tag: Label
var _tutorial_bubble: NinePatchRect
var _tutorial_label: Label
var _tutorial_tag: Label
var _tutorial_spring: UiSpring
var _time_spring: UiSpring
## 计时红闪用：上一次显示的剩余秒数
var _prev_seconds: int = -1

func setup(state: LevelState, level_name: String) -> void:
	_state = state
	layer = 20
	_build()
	_show_level_name(level_name)
	_state.hp_changed.connect(_on_hp)
	_state.time_changed.connect(_on_time)
	_state.tutorial_changed.connect(_on_tutorial)
	_on_hp(_state.hp, _state.max_hp)
	_on_time(_state.time_left, _state.elapsed, _state.timed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# ---- 左上角红心血量 ----
	var hearts_row: HBoxContainer = HBoxContainer.new()
	hearts_row.position = Vector2(36, 88)  # 避开分屏左上角的 P1 角标
	hearts_row.add_theme_constant_override("separation", 8)
	hearts_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hearts_row)
	for i: int in HEART_COUNT:
		var heart: TextureRect = TextureRect.new()
		heart.texture = MenuKit.heart_texture(0)
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.custom_minimum_size = Vector2(72, 64)
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts_row.add_child(heart)
		_hearts.append(heart)
		_heart_springs.append(UiSpring.attach(heart, 0.4, 0.4))

	# ---- 顶部中央计时面板 ----
	var time_panel: NinePatchRect = MenuKit.make_panel(Vector2(232, 96))
	time_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	time_panel.position = Vector2(-116, 20)
	time_panel.size = Vector2(232, 96)
	_root.add_child(time_panel)

	_time_label = MenuKit.make_label("00:00", 42, MenuKit.COL_INK, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_label.offset_top = 6.0
	time_panel.add_child(_time_label)
	_time_spring = UiSpring.attach(_time_label, 0.3, 0.4)

	_time_tag = MenuKit.make_label("", 14, Color(MenuKit.COL_INK, 0.55), 0)
	_time_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_tag.position = Vector2(-80, 10)
	_time_tag.size = Vector2(160, 18)
	time_panel.add_child(_time_tag)

	# ---- 底部教程气泡 ----
	_tutorial_bubble = MenuKit.make_dialog(Vector2(1000, 150))
	_tutorial_bubble.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tutorial_bubble.position = Vector2(-500, -190)
	_tutorial_bubble.size = Vector2(1000, 150)
	_tutorial_bubble.visible = false
	_root.add_child(_tutorial_bubble)
	_tutorial_spring = UiSpring.attach(_tutorial_bubble, 0.5, 0.35)

	_tutorial_tag = MenuKit.make_label("TIP 1/4", 28, MenuKit.COL_ACCENT, 0)
	_tutorial_tag.position = Vector2(64, 22)
	_tutorial_bubble.add_child(_tutorial_tag)

	_tutorial_label = MenuKit.make_label("", 28, MenuKit.COL_INK, 0)
	_tutorial_label.position = Vector2(64, 74)
	_tutorial_label.size = Vector2(880, 50)
	_tutorial_bubble.add_child(_tutorial_label)

## 开场关名提示：居中浮现后淡出
func _show_level_name(level_name: String) -> void:
	var toast: Label = MenuKit.make_label(level_name, 56)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_CENTER)
	toast.position = Vector2(-500, -220)
	toast.size = Vector2(1000, 80)
	_root.add_child(toast)
	UiSpring.attach(toast, 0.5, 0.3).pop_in(0.2)
	var tween: Tween = create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast.queue_free)

# ---------- 信号响应 ----------

## HP → 红心（半心粒度）；掉血时对应红心弹动
func _on_hp(hp: float, max_hp: float) -> void:
	var ratio: float = 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)
	var halves: int = int(round(ratio * float(HEART_COUNT) * 2.0))
	for i: int in HEART_COUNT:
		var heart_halves: int = clampi(halves - i * 2, 0, 2)
		# 0=空 1=半 2=满 → 贴图状态 2=空 1=半 0=满
		_hearts[i].texture = MenuKit.heart_texture(2 - heart_halves)
	if _prev_halves >= 0 and halves < _prev_halves:
		var idx: int = clampi((halves - 1) / 2 if halves > 0 else 0, 0, HEART_COUNT - 1)
		_heart_springs[idx].punch(0.5)
	_prev_halves = halves

func _on_time(time_left: float, elapsed: float, timed: bool) -> void:
	if timed:
		var t: int = int(ceil(time_left))
		_time_label.text = "%02d:%02d" % [t / 60, t % 60]
		_time_tag.text = "TIME LEFT"
		if time_left < 10.0:
			_time_label.label_settings.font_color = MenuKit.COL_DANGER
			# 每跳一秒红闪弹动
			if t != _prev_seconds:
				_time_spring.punch(0.25)
		else:
			_time_label.label_settings.font_color = MenuKit.COL_INK
		_prev_seconds = t
	else:
		var t: int = int(floor(elapsed))
		_time_label.text = "%02d:%02d" % [t / 60, t % 60]
		_time_tag.text = "PRACTICE"

func _on_tutorial(step_index: int, text: String) -> void:
	if text.is_empty():
		_tutorial_bubble.visible = false
		return
	_tutorial_bubble.visible = true
	_tutorial_tag.text = "TIP %d/%d" % [step_index + 1, _state.tutorial_texts.size()]
	_tutorial_label.text = text
	_tutorial_spring.punch(0.3)
