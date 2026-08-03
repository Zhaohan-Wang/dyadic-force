extends Control
## 结算界面：星级逐颗弹出 + 整局轨迹回放图 + 用时 / 生命 / 碰撞 / 平稳度。
## 刻意不展示任何单人输入量或贡献占比——只呈现"这一局大家一起跑成什么样"。

## 轨迹小地图：失败路线虚线淡绘，成功路线实线加粗
class TrailMap:
	extends Control
	var island_px: Vector2 = Vector2.ZERO
	## 通关成功的那条实线轨迹；失败结算可为空
	var trail: PackedVector2Array = PackedVector2Array()
	## 死亡 / 重置前的失败尝试
	var failed_trails: Array = []
	var hits: PackedVector2Array = PackedVector2Array()
	var spawn_p: Vector2 = Vector2.ZERO
	var goal_p: Vector2 = Vector2.ZERO
	## 迷你漩涡旋转相位
	var _spin: float = 0.0

	func _process(delta: float) -> void:
		_spin += delta * 2.4
		queue_redraw()

	func _draw() -> void:
		var bounds: Rect2 = _content_bounds()
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			return
		var pad: float = 24.0
		var s: float = minf(
			(size.x - pad * 2.0) / bounds.size.x,
			(size.y - pad * 2.0) / bounds.size.y
		)
		# 只对实际路线包围盒居中，不再为整座岛的空区域预留高度。
		var off: Vector2 = (size - bounds.size * s) * 0.5 - bounds.position * s

		# 先画失败路线（虚线 + 低透明），再画成功实线盖在上面
		for seg: Variant in failed_trails:
			var raw: PackedVector2Array = seg as PackedVector2Array
			if raw.size() < 2:
				continue
			_draw_dashed(_to_screen(raw, off, s), Color(MenuKit.COL_INK, 0.32), 4.5, 10.0, 8.0)

		if trail.size() >= 2:
			var pts: PackedVector2Array = _to_screen(trail, off, s)
			draw_polyline(pts, Color(MenuKit.COL_INK, 0.95), 8.5)

		# 出生点旗
		var sp: Vector2 = off + spawn_p * s
		draw_line(sp + Vector2(0.0, 12.0), sp + Vector2(0.0, -22.0), MenuKit.COL_INK, 4.0)
		var pennant: PackedVector2Array = PackedVector2Array([
			sp + Vector2(2.0, -22.0),
			sp + Vector2(24.0, -12.0),
			sp + Vector2(2.0, -4.0),
		])
		draw_colored_polygon(pennant, Color(0.30, 0.52, 0.88))

		# 传送门迷你漩涡
		var gp: Vector2 = off + goal_p * s
		draw_set_transform(gp, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, 15.0, _spin, _spin + TAU * 0.7, 22, Color(0.05, 0.55, 0.60), 3.6)
		draw_arc(Vector2.ZERO, 7.5, -_spin * 1.6, -_spin * 1.6 + TAU * 0.6, 18, Color(0.10, 0.70, 0.75), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		for h: Vector2 in hits:
			var c: Vector2 = off + h * s
			draw_rect(Rect2(c - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), MenuKit.COL_DANGER)

	## 根据路线内容宽高比给出紧凑高度；横向路线不再占据近半屏高度。
	func recommended_height(available_width: float) -> float:
		var bounds: Rect2 = _content_bounds()
		if bounds.size.x <= 0.0:
			return 180.0
		var aspect_height: float = (
			maxf(available_width - 48.0, 1.0)
			* bounds.size.y / bounds.size.x
			+ 48.0
		)
		return clampf(aspect_height, 150.0, 260.0)

	## 汇总成功/失败轨迹与标记点，得到真正有信息的世界坐标包围盒。
	func _content_bounds() -> Rect2:
		var points: PackedVector2Array = PackedVector2Array([spawn_p, goal_p])
		points.append_array(trail)
		points.append_array(hits)
		for seg: Variant in failed_trails:
			var failed: PackedVector2Array = seg as PackedVector2Array
			points.append_array(failed)
		if points.is_empty():
			return Rect2()
		var min_p: Vector2 = points[0]
		var max_p: Vector2 = points[0]
		for point: Vector2 in points:
			min_p.x = minf(min_p.x, point.x)
			min_p.y = minf(min_p.y, point.y)
			max_p.x = maxf(max_p.x, point.x)
			max_p.y = maxf(max_p.y, point.y)
		# 世界坐标留 24px：刚好容纳旗帜、传送门和线宽，不制造大块空白。
		var bounds: Rect2 = Rect2(min_p, max_p - min_p).grow(24.0)
		bounds.size.x = maxf(bounds.size.x, 1.0)
		bounds.size.y = maxf(bounds.size.y, 1.0)
		return bounds

	## 世界坐标 → 控件坐标
	func _to_screen(raw: PackedVector2Array, off: Vector2, s: float) -> PackedVector2Array:
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in raw:
			pts.append(off + p * s)
		return pts

	## 沿折线画虚线：dash 实段 + gap 空隙
	func _draw_dashed(
		pts: PackedVector2Array,
		color: Color,
		width: float,
		dash_len: float,
		gap_len: float,
	) -> void:
		if pts.size() < 2:
			return
		var draw_on: bool = true
		var budget: float = dash_len
		for i: int in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var remain: Vector2 = b - a
			var seg_len: float = remain.length()
			if seg_len < 0.001:
				continue
			var dir: Vector2 = remain / seg_len
			var cursor: Vector2 = a
			var left: float = seg_len
			while left > 0.001:
				var step: float = minf(budget, left)
				var nxt: Vector2 = cursor + dir * step
				if draw_on:
					draw_line(cursor, nxt, color, width)
				cursor = nxt
				left -= step
				budget -= step
				if budget <= 0.001:
					draw_on = not draw_on
					budget = dash_len if draw_on else gap_len

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())
	add_child(MenuKit.make_dim_overlay(0.5))

	var result: Dictionary = GameState.last_result
	var success: bool = bool(result.get("success", false))
	var stars: int = int(result.get("stars", 0))

	# 先准备路线数据，用实际内容宽高比决定地图和面板高度。
	var map: TrailMap = TrailMap.new()
	map.island_px = result.get("island", Vector2.ZERO) as Vector2
	map.trail = result.get("trail", PackedVector2Array()) as PackedVector2Array
	map.failed_trails = result.get("failed_trails", []) as Array
	map.hits = result.get("hits", PackedVector2Array()) as PackedVector2Array
	map.spawn_p = result.get("spawn", Vector2.ZERO) as Vector2
	map.goal_p = result.get("goal", Vector2.ZERO) as Vector2
	var map_height: float = map.recommended_height(692.0)

	# 固定内容约 500px，路线图按 180～300px 自适应；不再用 1000px 大空壳。
	var panel_height: float = clampf(500.0 + map_height, 650.0, 780.0)
	var panel_size: Vector2 = Vector2(780.0, panel_height)
	var panel: NinePatchRect = MenuKit.make_panel(panel_size)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	add_child(panel)
	UiSpring.attach(panel, 0.5, 0.3).pop_in(0.05)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 44.0
	box.offset_right = -44.0
	box.offset_top = 30.0
	box.offset_bottom = -30.0
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# ---- 主标题：结果口号，面板内强调色 + 硬阴影 ----
	var title: Label = MenuKit.make_title_label(
		"LEVEL CLEAR!" if success else "TIME'S UP!",
		48,
		MenuKit.COL_ACCENT if success else MenuKit.COL_DANGER,
		true,
	)
	box.add_child(title)

	# ---- 副标题：关名只负责定位，小一档墨色，零描边，绝不抢主标题 ----
	var name_label: Label = MenuKit.make_subtitle_label(
		str(result.get("level_name", "")).to_upper(),
		22,
	)
	box.add_child(name_label)

	# ---- 星级（代码烘焙的像素金星，未获得为空槽） ----
	var stars_row: HBoxContainer = HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 28)
	stars_row.custom_minimum_size = Vector2(0, 112)
	box.add_child(stars_row)
	for i: int in 3:
		var earned: bool = i < stars
		# 三颗星传不同 hold 时长，闪光节奏彼此错开
		var star: TextureRect = MenuKit.make_pixel_star(earned, 100.0, 1.1 + float(i) * 0.35)
		stars_row.add_child(star)
		var spring: UiSpring = UiSpring.attach(star, 0.5, 0.4)
		spring.pop_in(0.35 + float(i) * 0.18, 0.2 if earned else 0.6)

	# ---- 轨迹图：按真实路线包围盒紧凑显示 ----
	map.custom_minimum_size = Vector2(0.0, map_height)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.clip_contents = false
	box.add_child(map)

	# ---- 数据行 ----
	var elapsed: float = float(result.get("elapsed", 0.0))
	var t: int = int(floor(elapsed))
	box.add_child(_make_stat_row("TIME", "%02d:%02d" % [t / 60, t % 60]))
	var hp: float = float(result.get("hp", 0.0))
	var max_hp: float = float(result.get("max_hp", 100.0))
	box.add_child(_make_stat_row("HEARTS", "%d / %d" % [int(round(hp)), int(round(max_hp))]))
	var hit_count: int = (result.get("hits", PackedVector2Array()) as PackedVector2Array).size()
	box.add_child(_make_stat_row("BUMPS", str(hit_count)))
	box.add_child(_make_stat_row("RIDE", _stability_text(hit_count)))

	# ---- 按钮行 ----
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	box.add_child(actions)

	var retry: Button = _make_icon_button("RETRY", "retry")
	retry.pressed.connect(_on_retry)
	actions.add_child(retry)

	var select: Button = _make_icon_button("LEVELS", "levels")
	select.pressed.connect(func() -> void: SceneDirector.go_to("res://scenes/level_select.tscn"))
	actions.add_child(select)

	var next_path: String = GameState.next_level_path(str(result.get("level_id", "")))
	if success and next_path != "":
		var next_btn: Button = _make_icon_button("NEXT", "next")
		next_btn.pressed.connect(func() -> void:
			GameState.current_level = load(next_path) as LevelDef
			SceneDirector.go_to("res://scenes/level.tscn")
		)
		actions.add_child(next_btn)
		next_btn.grab_focus.call_deferred()
	else:
		var title_btn: Button = _make_icon_button("TITLE", "home")
		title_btn.pressed.connect(func() -> void:
			InputHub.clear_slots()
			SceneDirector.go_to("res://scenes/title_screen.tscn")
		)
		actions.add_child(title_btn)
		retry.grab_focus.call_deferred()

## 图标 + 文字的结算按钮
func _make_icon_button(text: String, icon_name: String) -> Button:
	var btn: Button = MenuKit.make_big_button(text, 24, Vector2(196, 96))
	btn.icon = MenuKit.make_button_icon(icon_name, 2)
	btn.add_theme_constant_override("h_separation", 10)
	btn.expand_icon = false
	return btn

## 轻度稳定状态：按碰撞次数给个定性描述，不做数值评分
func _stability_text(hit_count: int) -> String:
	if hit_count == 0:
		return "SMOOTH"
	if hit_count <= 2:
		return "STEADY"
	if hit_count <= 5:
		return "BUMPY"
	return "WILD"

## 一行结算数据：左名称右数值
func _make_stat_row(label_text: String, value_text: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label: Label = MenuKit.make_panel_label(label_text, 26, 0.55)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label: Label = MenuKit.make_panel_label(value_text, 26)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row

func _on_retry() -> void:
	if GameState.current_level != null:
		SceneDirector.go_to("res://scenes/level.tscn")
	else:
		SceneDirector.go_to("res://scenes/level_select.tscn")
