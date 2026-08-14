extends SceneTree
## 关卡布局审查：造真实世界 → 球心可达性 BFS → 路线指标（长度/最窄/弯道表）→ 导出真实美术预览图。
## 用法：godot --headless --path . --script res://tools/layout_audit.gd
## 预览图落在 docs/layout_previews/level_N_art.png（美术）与 level_N_debug.png（红点 = 球心到不了）。

## 探针用 preload 引入，免得依赖编辑器的全局类名缓存
const LayoutProbe: GDScript = preload("res://tools/layout_probe.gd")

const PREVIEW_DIR: String = "res://docs/layout_previews"
const PREVIEW_SCALE: float = 0.5
## 弯道统计阈值：累计转角超过这个度数才算一个弯
const TURN_MIN_DEG: float = 22.0

const LEVELS: Array[String] = [
	"res://levels/level_1.tres",
	"res://levels/level_2.tres",
	"res://levels/level_3.tres",
	"res://levels/level_4.tres",
	"res://levels/level_5.tres",
]

var _failures: int = 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	for path: String in LEVELS:
		_audit(path)
	if _failures > 0:
		print("layout_audit FAILED: %d problem(s)" % _failures)
		quit(1)
		return
	print("layout_audit OK")
	quit(0)

func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] %s" % msg)

func _audit(path: String) -> void:
	var def: LevelDef = load(path) as LevelDef
	if def == null:
		_fail("%s 读不出来" % path)
		return
	print("=== %s (%s) 岛屿 %dx%d 瓦 = %dx%d px ===" % [
		def.level_id, def.level_name, def.island_size.x, def.island_size.y,
		def.island_size.x * 16, def.island_size.y * 16,
	])

	var holder: Node2D = Node2D.new()
	root.add_child(holder)
	var probe: LayoutProbe = LayoutProbe.new()
	probe.build(def, holder)

	_report_route(def)
	_check_reach(def, probe)
	_save_previews(def, probe)

	holder.queue_free()

## 路线指标：各段长度、最窄通道、弯道表（左右/半径/位置）
func _report_route(def: LevelDef) -> void:
	var builder: WorldBuilder = WorldBuilder.new()
	var plan: WorldBuilder.LevelPlan = builder.plan_for(def.level_id)
	if plan.spine.is_empty():
		print("  （该关没有曲线计划）")
		return
	if plan.island != def.island_size:
		_fail("岛屿尺寸和计划不一致：tres %s vs plan %s" % [def.island_size, plan.island])

	var labels: PackedStringArray = PackedStringArray(["spine"])
	for branch: WorldBuilder.RouteBranch in plan.branches:
		labels.append(branch.label)
	var safe_total: float = 0.0
	for label: String in labels:
		var line: WorldBuilder.RouteLine = builder.sampled_route(plan, label)
		var length: float = line.length()
		if plan.centerline_order.has(label):
			safe_total += length
		print("  段 %-14s 长 %6.0f px   最窄通道 %5.0f px   起 %s 终 %s" % [
			label, length, line.min_half() * 2.0,
			line.points[0].round(), line.points[-1].round(),
		])
		if line.min_half() * 2.0 < 164.0:
			_fail("%s 段通道 %.0f px 太窄（球直径 88，最低建议 164）" % [label, line.min_half() * 2.0])
	print("  安全路线总长 %.0f px" % safe_total)

	var turns: Array[Dictionary] = []
	for label: String in plan.centerline_order:
		turns.append_array(_turns_of(builder.sampled_route(plan, label)))
	var left: int = 0
	var right: int = 0
	for turn: Dictionary in turns:
		if str(turn["dir"]) == "左":
			left += 1
		else:
			right += 1
	print("  弯道 %d 个（左 %d / 右 %d）：" % [turns.size(), left, right])
	for turn: Dictionary in turns:
		print("    %s弯 %5.1f°  半径 %5.0f  顶点 %s  通道 %.0f px" % [
			turn["dir"], turn["deg"], turn["radius"], (turn["apex"] as Vector2).round(),
			float(turn["half"]) * 2.0,
		])

	# 中心线拼接结果：可直接粘进 tres
	var centerline: PackedVector2Array = _safe_centerline(builder, plan)
	print("  出生点建议 %s / 终点建议 %s" % [centerline[0].round(), centerline[-1].round()])
	if centerline[0].distance_to(def.spawn_point) > 1.0:
		_fail("tres spawn_point %s 与路线起点 %s 不一致" % [def.spawn_point, centerline[0].round()])
	if centerline[-1].distance_to(def.goal_point) > 1.0:
		_fail("tres goal_point %s 与路线终点 %s 不一致" % [def.goal_point, centerline[-1].round()])
	print("  route_centerline = %s" % _packed_literal(centerline))

## 取安全（宽）路线的抽稀中心线，约每 180px 一个点
func _safe_centerline(builder: WorldBuilder, plan: WorldBuilder.LevelPlan) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for label: String in plan.centerline_order:
		var line: WorldBuilder.RouteLine = builder.sampled_route(plan, label)
		var acc: float = 0.0
		for i: int in line.points.size():
			var p: Vector2 = line.points[i]
			if i > 0:
				acc += line.points[i - 1].distance_to(p)
			var is_end: bool = i == line.points.size() - 1
			if out.is_empty() or acc >= 180.0 or is_end:
				if out.is_empty() or out[-1].distance_to(p) > 1.0:
					out.append(p.round())
				acc = 0.0
	return out

## 弯道识别：按朝向变化分组，累计转角超阈值即计一个弯
func _turns_of(line: WorldBuilder.RouteLine) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if line.points.size() < 4:
		return out
	var run_sign: float = 0.0
	var run_deg: float = 0.0
	var run_len: float = 0.0
	var run_apex: Vector2 = Vector2.ZERO
	var run_half: float = 0.0
	var run_peak: float = 0.0
	var flat_len: float = 0.0
	for i: int in range(1, line.points.size() - 1):
		var d0: Vector2 = line.points[i] - line.points[i - 1]
		var d1: Vector2 = line.points[i + 1] - line.points[i]
		if d0.length() < 0.01 or d1.length() < 0.01:
			continue
		var dtheta: float = wrapf(d1.angle() - d0.angle(), -PI, PI)
		var seg: float = d1.length()
		var sign_now: float = signf(dtheta)
		if absf(dtheta) < 0.004:
			flat_len += seg
			if flat_len > 150.0 and run_deg > 0.0:
				_close_turn(out, run_sign, run_deg, run_len, run_apex, run_half)
				run_sign = 0.0
				run_deg = 0.0
				run_len = 0.0
				run_peak = 0.0
			continue
		flat_len = 0.0
		if run_sign != 0.0 and sign_now != run_sign:
			_close_turn(out, run_sign, run_deg, run_len, run_apex, run_half)
			run_deg = 0.0
			run_len = 0.0
			run_peak = 0.0
		run_sign = sign_now
		run_deg += rad_to_deg(absf(dtheta))
		run_len += seg
		if absf(dtheta) > run_peak:
			run_peak = absf(dtheta)
			run_apex = line.points[i]
			run_half = line.halves[i]
	_close_turn(out, run_sign, run_deg, run_len, run_apex, run_half)
	return out

func _close_turn(
	out: Array[Dictionary],
	run_sign: float,
	run_deg: float,
	run_len: float,
	apex: Vector2,
	half: float
) -> void:
	if run_sign == 0.0 or run_deg < TURN_MIN_DEG:
		return
	out.append({
		# 屏幕 y 向下：朝向角变大 = 顺时针 = 行进方向的右手边
		"dir": "右" if run_sign > 0.0 else "左",
		"deg": run_deg,
		"radius": run_len / maxf(0.001, deg_to_rad(run_deg)),
		"apex": apex,
		"half": half,
	})

## 可达性：出生、终点、中心线每个折点、路段矩形、岔路提交线、门口
func _check_reach(def: LevelDef, probe: LayoutProbe) -> void:
	if not probe.is_free(def.spawn_point):
		_fail("出生点被挡住 %s" % def.spawn_point)
	if not probe.is_reachable(def.goal_point):
		_fail("终点不可达 %s" % def.goal_point)
	var off_route: int = 0
	for i: int in def.route_centerline.size():
		if not probe.reachable_near(def.route_centerline[i], 2):
			off_route += 1
			if off_route <= 4:
				_fail("中心线第 %d 点不可达 %s" % [i, def.route_centerline[i]])
	for seg: SegmentDef in def.segments:
		if not probe.reachable_near(seg.as_rect().get_center(), 8):
			_fail("路段 %s 中心不可达 %s" % [seg.segment_id, seg.as_rect().get_center()])
	for gate: GateDef in def.gates:
		if not probe.reachable_near(gate.position, 3):
			_fail("门 %s 位置不在通道上 %s" % [gate.gate_id, gate.position])
	for fork: ChoiceForkDef in def.choice_forks:
		if not probe.reachable_near(fork.approach_rect().get_center(), 8):
			_fail("岔路 %s 观察区中心不可达" % fork.fork_id)
		for mid: Vector2 in [
			(fork.commit_a_from + fork.commit_a_to) * 0.5,
			(fork.commit_b_from + fork.commit_b_to) * 0.5,
		]:
			if not probe.reachable_near(mid, 4):
				_fail("岔路 %s 提交线中点不可达 %s" % [fork.fork_id, mid])
	print("  可达格数 %d（8px 网格）" % probe.reachable_cells())

## 导出真实美术预览 + 调试图
func _save_previews(def: LevelDef, probe: LayoutProbe) -> void:
	var art: Image = probe.render_art()
	var debug: Image = art.duplicate() as Image
	probe.shade_unreachable(debug)
	for i: int in range(def.route_centerline.size() - 1):
		probe.draw_line_on(debug, def.route_centerline[i], def.route_centerline[i + 1], Color(1.0, 0.55, 0.0), 2)
	for seg: SegmentDef in def.segments:
		probe.draw_rect_on(debug, seg.as_rect(), Color(0.1, 0.4, 1.0))
	for fork: ChoiceForkDef in def.choice_forks:
		probe.draw_rect_on(debug, fork.approach_rect(), Color(1.0, 0.9, 0.1))
		probe.draw_line_on(debug, fork.commit_a_from, fork.commit_a_to, Color(0.1, 1.0, 0.4), 2)
		probe.draw_line_on(debug, fork.commit_b_from, fork.commit_b_to, Color(0.1, 1.0, 1.0), 2)
	for gate: GateDef in def.gates:
		probe.draw_rect_on(debug, Rect2(gate.position - Vector2(14.0, gate.opening_width * 0.5),
			Vector2(28.0, gate.opening_width)), Color(0.9, 0.2, 0.9))
	probe.draw_rect_on(debug, Rect2(def.spawn_point - Vector2(22.0, 22.0), Vector2(44.0, 44.0)), Color(1, 1, 1))
	probe.draw_rect_on(debug, Rect2(def.goal_point - Vector2(22.0, 22.0), Vector2(44.0, 44.0)), Color(0, 0, 0))

	# 1:1 特写：全图缩略会低估植被密度，按玩家实际视野截一块出来看
	# 小岛可能比截图框还小，先夹住尺寸，免得截出空白边
	var crop_size: Vector2i = Vector2i(
		mini(1120, art.get_width()), mini(720, art.get_height())
	)
	var crop_at: Vector2i = Vector2i(
		clampi(int(def.spawn_point.x) - 260, 0, maxi(0, art.get_width() - crop_size.x)),
		clampi(int(def.spawn_point.y) - 260, 0, maxi(0, art.get_height() - crop_size.y))
	)
	var closeup: Image = art.get_region(Rect2i(crop_at, crop_size))
	closeup.save_png("%s/%s_closeup.png" % [PREVIEW_DIR, def.level_id])

	var size: Vector2i = Vector2i(Vector2(art.get_size()) * PREVIEW_SCALE)
	art.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	debug.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	art.save_png("%s/%s_art.png" % [PREVIEW_DIR, def.level_id])
	debug.save_png("%s/%s_debug.png" % [PREVIEW_DIR, def.level_id])
	print("  预览图已写出 %s_art / _debug / _closeup.png" % def.level_id)

## 把点列打成 tres 能直接用的字面量
func _packed_literal(points: PackedVector2Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p: Vector2 in points:
		parts.append("%d, %d" % [int(p.x), int(p.y)])
	return "PackedVector2Array(%s)" % ", ".join(parts)
