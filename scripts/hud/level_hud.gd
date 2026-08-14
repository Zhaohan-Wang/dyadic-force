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
var _time_label: Control
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
const COL_JAM_HOT: Color = Color("c084fc")
var _dampen_window: Vector2 = Vector2.ZERO
var _dampen_mark: ColorRect = null
var _dampen_label: Control = null
var _timer_frame: NinePatchRect = null
## 钟表旁实时增益徽章（干扰进行中才显示）
var _jam_badge: Control = null
var _jam_badge_label: Control = null
var _jam_slot: int = -1
var _jam_factor: float = 1.0
var _clock_base_modulate: Color = Color.WHITE
## 扰动开始时的已用时（秒）；-1 = 当前没有扰动
var _skew_start_elapsed: float = -1.0
## 正在生长的那段标记（深色描边框）；结束后留在条上当历史刻度，不回收
var _skew_band: ColorRect = null
## 描边框内部的琥珀色实体
var _skew_band_fill: ColorRect = null
var _skew_badge: Control = null
var _skew_badge_label: Control = null
var _skew_lamp: ColorRect = null
## 第 4 关：计时器从开局就亮「干扰」灯，不等人走进候选段
var _show_jam_lamp: bool = false

func setup(
	state: LevelState,
	level_name: String,
	total_time: float = 0.0,
	dampen_window: Vector2 = Vector2.ZERO,
	show_jam_lamp: bool = false,
) -> void:
	_state = state
	_time_total = total_time
	_dampen_window = dampen_window
	_show_jam_lamp = show_jam_lamp
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
	_tutorial_tag = MenuKit.make_label(
		GameState.ui("提示 1/4", "TIP 1/4"), 22, MenuKit.COL_ACCENT, 0
	)
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
	_timer_frame = frame

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

	# 紫色干扰带叠在填充之上，否则绿条会完全盖住
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
	_clock_base_modulate = _clock.modulate

	_build_jam_badge(frame)

	# 秒数：条下方世界字幕，轻描边保证草地上可读，但不抢进度条本体
	_time_label = MenuKit.make_pixel_outline_text("00:00", 32, MenuKit.COL_CREAM, 3)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(-110, 84)
	_time_label.size = Vector2(220, 48)
	_root.add_child(_time_label)

	_build_skew_badge()
	if _show_jam_lamp:
		# 第四关一进关就亮灯：玩家必须一眼看见「这里会干扰」
		_show_jam_lamp_idle()

## 时间轴上的“输入缩减”警示带：
## 进度条从右往左缩短，已用时 t 对应位置 x = inner_x + inner_w * (1 - t/total)，
## 因此时段 [start, end] 在条上是 [pos(end), pos(start)] 这段区间。
func _build_dampen_mark(frame: NinePatchRect) -> void:
	var x_left: float = _bar_inner_x \
		+ _bar_inner_w * (1.0 - clampf(_dampen_window.y / _time_total, 0.0, 1.0))
	var x_right: float = _bar_inner_x \
		+ _bar_inner_w * (1.0 - clampf(_dampen_window.x / _time_total, 0.0, 1.0))
	var band_w: float = maxf(x_right - x_left, 8.0)
	# 底衬：更深一档，绿条盖不住时仍能认出干扰区
	var under: ColorRect = ColorRect.new()
	under.position = Vector2(x_left, 14.0)
	under.size = Vector2(band_w, 36.0)
	under.color = Color(COL_JAM, 0.55)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(under)
	_dampen_mark = under
	# 两端实心竖线刻度
	for x: float in [x_left, x_left + band_w - 4.0]:
		var tick: ColorRect = ColorRect.new()
		tick.position = Vector2(x, 12.0)
		tick.size = Vector2(4.0, 40.0)
		tick.color = COL_JAM_HOT
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tick)
	# 带上标签：JAM / 干扰
	_dampen_label = MenuKit.make_pixel_outline_text(
		GameState.ui("干扰", "JAM"), 18, COL_JAM_HOT, 2
	)
	_dampen_label.position = Vector2(x_left + 6.0, -2.0)
	_dampen_label.size = Vector2(80.0, 24.0)
	_dampen_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_dampen_label)

## 钟表旁增益徽章：显示被砍的是 P1/P2，以及当前百分比
func _build_jam_badge(frame: NinePatchRect) -> void:
	_jam_badge = Control.new()
	_jam_badge.visible = false
	_jam_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jam_badge.size = Vector2(120, 36)
	frame.add_child(_jam_badge)
	var bg: ColorRect = ColorRect.new()
	bg.name = "Bg"
	bg.size = Vector2(120, 32)
	bg.color = Color(COL_JAM, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jam_badge.add_child(bg)
	_jam_badge_label = MenuKit.make_pixel_outline_text("P1 50%", 18, MenuKit.COL_CREAM, 2)
	_jam_badge_label.position = Vector2(6, 4)
	_jam_badge_label.size = Vector2(110, 28)
	_jam_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jam_badge.add_child(_jam_badge_label)

## 关卡通知：slot=-1 表示干扰结束；factor 为被缩减玩家的增益（约 0.5）。
func set_dampen_active(slot: int, factor: float) -> void:
	_jam_slot = slot
	_jam_factor = factor
	if _jam_badge == null or _clock == null:
		return
	if slot < 0:
		_jam_badge.visible = false
		_clock.modulate = _clock_base_modulate
		return
	var pct: int = int(round(factor * 100.0))
	var text: String = GameState.ui("P%d %d%%" % [slot + 1, pct], "P%d %d%%" % [slot + 1, pct])
	MenuKit.set_pixel_outline_text(_jam_badge_label, text)
	_jam_badge.visible = true
	_clock.modulate = COL_JAM_HOT
	if _clock_spring != null:
		_clock_spring.punch(0.7)

## 「干扰」灯：秒数正下方居中。第四关从开局就亮，扰动进行中再加亮。
func _build_skew_badge() -> void:
	_skew_badge = Control.new()
	_skew_badge.visible = false
	_skew_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skew_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_skew_badge.position = Vector2(-78, 132)
	_skew_badge.size = Vector2(156, 36)
	_root.add_child(_skew_badge)
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(156, 34)
	bg.color = Color(COL_JAM, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skew_badge.add_child(bg)
	# 左侧圆点就是「灯」：待命暗紫，扰动中亮紫闪
	_skew_lamp = ColorRect.new()
	_skew_lamp.position = Vector2(10, 10)
	_skew_lamp.size = Vector2(14, 14)
	_skew_lamp.color = COL_JAM_HOT
	_skew_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skew_badge.add_child(_skew_lamp)
	_skew_badge_label = MenuKit.make_pixel_outline_text(
		GameState.ui("干扰", "JAM"), 20, MenuKit.COL_CREAM, 2
	)
	_skew_badge_label.position = Vector2(32, 4)
	_skew_badge_label.size = Vector2(116, 28)
	_skew_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skew_badge.add_child(_skew_badge_label)

## 开局待命态：灯常亮，钟表带一点紫色，告诉玩家本关会干扰
func _show_jam_lamp_idle() -> void:
	if _skew_badge != null:
		_skew_badge.visible = true
	if _clock != null:
		_clock.modulate = COL_JAM
	if _time_label != null:
		MenuKit.set_pixel_outline_color(_time_label, COL_JAM_HOT)

## 关卡通知：隐藏扰动开始（active=true）/ 结束。
## 时间条上开一段琥珀色标记，秒数与钟表同时变色，玩家能看出"刚才那段被动过手脚"。
func set_perturb_active(active: bool, elapsed: float) -> void:
	# 第四关的「干扰」灯从开局就亮；扰动结束也不关，只退回待命色
	if _skew_badge != null:
		_skew_badge.visible = _show_jam_lamp or active
	if active:
		_skew_start_elapsed = elapsed
		_skew_band = _make_skew_band(elapsed)
		if _clock != null:
			_clock.modulate = COL_JAM_HOT
		if _clock_spring != null:
			_clock_spring.punch(0.8)
	else:
		_skew_start_elapsed = -1.0
		if _skew_band_fill != null:
			# 结束后压暗一档，和正在进行的那段区分开
			_skew_band_fill.color = Color(COL_JAM, 0.8)
			_skew_band_fill = null
		_skew_band = null
		if _clock != null:
			if _show_jam_lamp:
				_clock.modulate = COL_JAM
			elif _jam_slot >= 0:
				_clock.modulate = COL_JAM_HOT
			else:
				_clock.modulate = _clock_base_modulate
	if _time_label != null:
		var label_color: Color = MenuKit.COL_CREAM
		if active:
			label_color = COL_JAM_HOT
		elif _show_jam_lamp:
			label_color = COL_JAM_HOT
		MenuKit.set_pixel_outline_color(_time_label, label_color)

## 时间条上的已用时坐标：条从右往左缩短，已用 t 秒对应 x = inner_x + inner_w * (1 - t/total)
func _bar_x_for(seconds: float) -> float:
	return _bar_inner_x \
		+ _bar_inner_w * (1.0 - clampf(seconds / _time_total, 0.0, 1.0))

## 新开一段扰动标记（宽度随时间往左长）；练习关没有时间条时返回 null。
## 倒计时条中段本身就是琥珀色，所以标记必须带深色描边才认得出来。
func _make_skew_band(elapsed: float) -> ColorRect:
	if _timer_frame == null or _time_total <= 0.0:
		_skew_band_fill = null
		return null
	var band: ColorRect = ColorRect.new()
	# 和轨道同高同顶：紫色只铺在时间轴里面，不再探出面板
	band.position = Vector2(_bar_x_for(elapsed) - 8.0, 20.0)
	band.size = Vector2(8.0, 24.0)
	band.color = Color(MenuKit.COL_INK, 0.7)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_frame.add_child(band)
	# 排在钟表之前：竖条压在表盘上会把表糊掉
	if _clock != null:
		_timer_frame.move_child(band, _clock.get_index())
	_skew_band_fill = ColorRect.new()
	_skew_band_fill.position = Vector2(1.0, 1.0)
	_skew_band_fill.size = band.size - Vector2(2.0, 2.0)
	_skew_band_fill.color = Color(COL_JAM_HOT, 0.95)
	_skew_band_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(_skew_band_fill)
	return band

## 练习关：世界字幕级 PRACTICE 标签——交代"无倒计时"，不抢红心与教程气泡
func _build_practice_tag() -> void:
	_time_label = MenuKit.make_pixel_outline_text(
		GameState.ui("练习 00:00", "PRACTICE 00:00"), 32, MenuKit.COL_CREAM, 3
	)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(-220, 24)
	_time_label.size = Vector2(440, 44)
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
	var toast: Control = MenuKit.make_pixel_outline_text(
		GameState.localize_content(level_name), 56, MenuKit.COL_CREAM, 3
	)
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
	# 半心刻度；血量已在 LevelState 吸附到 0.5，这里不再用会抹掉残血的 round 糊弄。
	var halves: int = clampi(int(floor(hp * 2.0 + 0.001)), 0, HEART_COUNT * 2)
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
		if t != _prev_seconds:
			MenuKit.set_pixel_outline_text(_time_label, "%02d:%02d" % [t / 60, t % 60])
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
		# 增益徽章贴在钟表左侧，跟随钟表移动
		if _jam_badge != null:
			_jam_badge.position = Vector2(_clock.position.x - 128.0, 8.0)
		# “输入缩减”时段：警示带呼吸；进行中更亮
		if _dampen_mark != null:
			var inside: bool = elapsed >= _dampen_window.x and elapsed < _dampen_window.y
			var active: bool = _jam_slot >= 0
			var mark_a: float = 0.45
			if active:
				mark_a = 0.72 + 0.22 * sin(elapsed * 9.0)
			elif inside:
				mark_a = 0.55 + 0.15 * sin(elapsed * 6.0)
			_dampen_mark.color = Color(COL_JAM if not active else COL_JAM_HOT, mark_a)
			if _dampen_label != null:
				_dampen_label.modulate.a = 1.0 if (inside or active) else 0.75
		# 第四关干扰灯：待命慢闪，扰动中快闪
		if _show_jam_lamp and _skew_lamp != null:
			var lamp_hot: bool = _skew_start_elapsed >= 0.0
			var pulse: float = 0.72 + 0.28 * sin(elapsed * (10.0 if lamp_hot else 3.2))
			_skew_lamp.color = Color(COL_JAM_HOT if lamp_hot else COL_JAM, pulse)
		# 扰动进行中：标记从"当前时刻"往左长，并做呼吸闪烁
		if _skew_band != null and _skew_start_elapsed >= 0.0:
			var x_right: float = _bar_x_for(_skew_start_elapsed)
			var x_left: float = _bar_x_for(elapsed)
			_skew_band.position.x = x_left
			_skew_band.size.x = maxf(x_right - x_left, 8.0)
			if _skew_band_fill != null:
				_skew_band_fill.size = _skew_band.size - Vector2(2.0, 2.0)
				_skew_band_fill.color = Color(
					COL_JAM_HOT, 0.78 + 0.2 * sin(elapsed * 9.0)
				)
		# 时间紧张：每跳一秒钟表蹦一下（越紧张越用力）
		if t != _prev_seconds and (ratio < 0.3 or time_left < 12.0):
			_clock_spring.punch(0.65 if time_left < 12.0 else 0.4)
		if time_left < 12.0:
			MenuKit.set_pixel_outline_color(_time_label, MenuKit.COL_DANGER)
		elif _show_jam_lamp:
			# 每秒改字不会丢色：第四关秒数一直保持紫色
			MenuKit.set_pixel_outline_color(_time_label, COL_JAM_HOT)
		_prev_seconds = t
	else:
		var t: int = int(floor(elapsed))
		if t != _prev_seconds:
			MenuKit.set_pixel_outline_text(
				_time_label,
				GameState.ui(
					"练习 %02d:%02d" % [t / 60, t % 60],
					"PRACTICE %02d:%02d" % [t / 60, t % 60],
				),
			)
		_prev_seconds = t

func _on_tutorial(step_index: int, text: String) -> void:
	if text.is_empty():
		_tutorial_bubble.visible = false
		return
	_tutorial_bubble.visible = true
	MenuKit.set_label_text(
		_tutorial_tag,
		GameState.ui(
			"提示 %d/%d" % [step_index + 1, _state.tutorial_texts.size()],
			"TIP %d/%d" % [step_index + 1, _state.tutorial_texts.size()],
		),
	)
	MenuKit.set_label_text(_tutorial_label, GameState.localize_content(text))
	_tutorial_spring.punch(0.3)
