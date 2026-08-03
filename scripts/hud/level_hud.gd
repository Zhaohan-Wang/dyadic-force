class_name LevelHud
extends CanvasLayer
## 关卡 HUD：红心血量、计时面板、教程对话气泡、开场关名提示。
## 只订阅 LevelState 信号，不直接接触关卡逻辑。

## 固定三格整心（与 LevelDef.ball_max_hp = 3 对齐）
const HEART_COUNT: int = 3

var _state: LevelState
var _root: Control
## 红心节点与其弹簧
var _hearts: Array[TextureRect] = []
var _heart_springs: Array[UiSpring] = []
## 上一次显示的半心数（0～6；掉血时弹动对应那颗）
var _prev_halves: int = -1
var _time_label: Label
var _tutorial_bubble: NinePatchRect
var _tutorial_label: Label
var _tutorial_tag: Label
var _tutorial_spring: UiSpring
## 计时红闪用：上一次显示的剩余秒数
var _prev_seconds: int = -1
## 倒计时进度条（仅正式关）
var _time_total: float = 0.0
var _bar_fill: ColorRect
var _bar_inner_x: float = 0.0
var _bar_inner_w: float = 0.0
var _clock: TextureRect
var _clock_spring: UiSpring
## “输入缩减”时段（x=开始秒 y=结束秒；ZERO = 无）与时间轴上的警示带
const COL_JAM: Color = Color("8a5cf5")
var _dampen_window: Vector2 = Vector2.ZERO
var _dampen_mark: ColorRect = null

func setup(
	state: LevelState,
	level_name: String,
	total_time: float = 0.0,
	dampen_window: Vector2 = Vector2.ZERO,
) -> void:
	_state = state
	_time_total = total_time
	_dampen_window = dampen_window
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
		heart.custom_minimum_size = Vector2(80, 72)
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts_row.add_child(heart)
		_hearts.append(heart)
		_heart_springs.append(UiSpring.attach(heart, 0.4, 0.4))

	# ---- 顶部计时：正式关 = 钟表 + 缩短进度条；练习关 = 小标签 ----
	if _state.timed:
		_build_timer_bar()
	else:
		_build_practice_tag()

	# ---- 底部教程气泡 ----
	_tutorial_bubble = MenuKit.make_dialog(Vector2(1000, 150))
	_tutorial_bubble.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tutorial_bubble.position = Vector2(-500, -190)
	_tutorial_bubble.size = Vector2(1000, 150)
	_tutorial_bubble.visible = false
	_root.add_child(_tutorial_bubble)
	_tutorial_spring = UiSpring.attach(_tutorial_bubble, 0.5, 0.35)

	# TIP 标签：小一档强调色，只做步骤索引；正文才是阅读主体
	_tutorial_tag = MenuKit.make_label("TIP 1/4", 20, MenuKit.COL_ACCENT, 0)
	_tutorial_tag.position = Vector2(64, 24)
	_tutorial_bubble.add_child(_tutorial_tag)

	_tutorial_label = MenuKit.make_panel_label("", 28)
	_tutorial_label.position = Vector2(64, 70)
	_tutorial_label.size = Vector2(880, 50)
	_tutorial_bubble.add_child(_tutorial_label)

## 正式关倒计时条：长条从右往左缩短、绿→红渐变，
## 钟表图标骑在缩短的那端一路向左走，时间紧张时蹦蹦跳跳。
func _build_timer_bar() -> void:
	var bar_w: float = 640.0
	var bar_h: float = 64.0
	var frame: NinePatchRect = MenuKit.make_panel(Vector2(bar_w, bar_h))
	frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	frame.position = Vector2(-bar_w * 0.5, 24)
	frame.size = Vector2(bar_w, bar_h)
	_root.add_child(frame)

	# 轨道底（比填充深一点，空的部分看得出"已流逝"）
	_bar_inner_x = 18.0
	_bar_inner_w = bar_w - 36.0
	var track: ColorRect = ColorRect.new()
	track.position = Vector2(_bar_inner_x, 20.0)
	track.size = Vector2(_bar_inner_w, 24.0)
	track.color = Color(MenuKit.COL_INK, 0.22)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(track)

	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(_bar_inner_x, 20.0)
	_bar_fill.size = Vector2(_bar_inner_w, 24.0)
	_bar_fill.color = MenuKit.COL_READY
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_bar_fill)

	# “输入缩减”时段：紫色警示带叠在时间轴对应区间上（比轨道略高，读作"区域"）
	if _dampen_window != Vector2.ZERO and _time_total > 0.0:
		_build_dampen_mark(frame)

	_clock = TextureRect.new()
	_clock.texture = _make_clock_texture()
	_clock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_clock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clock.custom_minimum_size = Vector2(56, 56)
	_clock.size = Vector2(56, 56)
	_clock.position = Vector2(_bar_inner_x + _bar_inner_w - 28.0, 4.0)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_clock)
	_clock_spring = UiSpring.attach(_clock, 0.35, 0.4)

	# 秒数：条下方世界字幕，轻描边保证草地上可读，但不抢进度条本体
	_time_label = MenuKit.make_world_caption("00:00", 20)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(-60, 92)
	_time_label.size = Vector2(120, 24)
	_root.add_child(_time_label)

## 时间轴上的“输入缩减”警示带：
## 进度条从右往左缩短，已用时 t 对应位置 x = inner_x + inner_w * (1 - t/total)，
## 因此时段 [start, end] 在条上是 [pos(end), pos(start)] 这段区间。
func _build_dampen_mark(frame: NinePatchRect) -> void:
	var x_left: float = _bar_inner_x \
		+ _bar_inner_w * (1.0 - clampf(_dampen_window.y / _time_total, 0.0, 1.0))
	var x_right: float = _bar_inner_x \
		+ _bar_inner_w * (1.0 - clampf(_dampen_window.x / _time_total, 0.0, 1.0))
	# 主警示带：比轨道上下各高出 4px，半透明盖在填充之上
	_dampen_mark = ColorRect.new()
	_dampen_mark.position = Vector2(x_left, 16.0)
	_dampen_mark.size = Vector2(x_right - x_left, 32.0)
	_dampen_mark.color = Color(COL_JAM, 0.4)
	_dampen_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_dampen_mark)
	# 两端实心竖线刻度，标出时段边界
	for x: float in [x_left, x_right - 3.0]:
		var tick: ColorRect = ColorRect.new()
		tick.position = Vector2(x, 16.0)
		tick.size = Vector2(3.0, 32.0)
		tick.color = COL_JAM
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tick)

## 练习关：世界字幕级 PRACTICE 标签——交代"无倒计时"，不抢红心与教程气泡
func _build_practice_tag() -> void:
	_time_label = MenuKit.make_world_caption("PRACTICE 00:00", 20)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(-180, 28)
	_time_label.size = Vector2(360, 32)
	_root.add_child(_time_label)

## 烘焙 16x16 像素闹钟图标（表壳 + 表盘 + 指针 + 双铃）
func _make_clock_texture() -> Texture2D:
	var ink: Color = MenuKit.COL_INK
	var cream: Color = MenuKit.COL_CREAM
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in 16:
		for x: int in 16:
			var d: float = Vector2(float(x) - 7.5, float(y) - 8.5).length()
			if d <= 6.5 and d > 5.0:
				img.set_pixel(x, y, ink)
			elif d <= 5.0:
				img.set_pixel(x, y, cream)
	# 分针朝上、时针朝右
	for y: int in range(5, 9):
		img.set_pixel(7, y, ink)
	for x: int in range(8, 11):
		img.set_pixel(x, 8, ink)
	# 顶部双铃
	img.set_pixel(3, 1, ink)
	img.set_pixel(4, 2, ink)
	img.set_pixel(12, 1, ink)
	img.set_pixel(11, 2, ink)
	return ImageTexture.create_from_image(img)

## 进度条颜色：>50% 绿→琥珀，<50% 琥珀→红
func _bar_color(ratio: float) -> Color:
	if ratio > 0.5:
		return MenuKit.COL_ACCENT.lerp(MenuKit.COL_READY, (ratio - 0.5) * 2.0)
	return MenuKit.COL_DANGER.lerp(MenuKit.COL_ACCENT, ratio * 2.0)

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

## HP → 三格红心（满 / 半 / 空）；掉血时对应红心弹动
func _on_hp(hp: float, _max_hp: float) -> void:
	# 3 心 × 2 = 6 个半心刻度，和浮点伤对齐
	var halves: int = clampi(int(round(hp * 2.0)), 0, HEART_COUNT * 2)
	for i: int in HEART_COUNT:
		var heart_halves: int = clampi(halves - i * 2, 0, 2)
		# 0=空 1=半 2=满 → 贴图状态 2=空 1=半 0=满
		_hearts[i].texture = MenuKit.heart_texture(2 - heart_halves)
	if _prev_halves >= 0 and halves < _prev_halves:
		var idx: int = clampi((halves) / 2, 0, HEART_COUNT - 1)
		_heart_springs[idx].punch(0.55)
	_prev_halves = halves

func _on_time(time_left: float, elapsed: float, timed: bool) -> void:
	if timed:
		var t: int = int(ceil(time_left))
		_time_label.text = "%02d:%02d" % [t / 60, t % 60]
		# 长条从右往左缩短，颜色随比例绿→红
		var ratio: float = 1.0 if _time_total <= 0.0 \
			else clampf(time_left / _time_total, 0.0, 1.0)
		_bar_fill.size.x = _bar_inner_w * ratio
		_bar_fill.color = _bar_color(ratio)
		# 钟表骑在缩短的那端一路向左走
		_clock.position.x = clampf(
			_bar_inner_x + _bar_inner_w * ratio - 28.0,
			_bar_inner_x - 16.0, _bar_inner_x + _bar_inner_w - 28.0
		)
		# “输入缩减”进行中：警示带呼吸脉动提醒玩家正处于该时段
		if _dampen_mark != null:
			var inside: bool = elapsed >= _dampen_window.x and elapsed < _dampen_window.y
			var mark_a: float = 0.55 + 0.25 * sin(elapsed * 7.0) if inside else 0.4
			_dampen_mark.color = Color(COL_JAM, mark_a)
		# 时间紧张：每跳一秒钟表蹦一下（越紧张越用力）
		if t != _prev_seconds and (ratio < 0.3 or time_left < 12.0):
			_clock_spring.punch(0.65 if time_left < 12.0 else 0.4)
		if time_left < 12.0:
			_time_label.label_settings.font_color = MenuKit.COL_DANGER
		_prev_seconds = t
	else:
		var t: int = int(floor(elapsed))
		_time_label.text = "PRACTICE %02d:%02d" % [t / 60, t % 60]

func _on_tutorial(step_index: int, text: String) -> void:
	if text.is_empty():
		_tutorial_bubble.visible = false
		return
	_tutorial_bubble.visible = true
	_tutorial_tag.text = "TIP %d/%d" % [step_index + 1, _state.tutorial_texts.size()]
	_tutorial_label.text = text
	_tutorial_spring.punch(0.3)
