extends SceneTree
## 五关可达性断言：直接用 WorldBuilder 造关（不加载 level.tscn），对球心做网格 BFS（R=44）。
## 检查点全部从 LevelDef 自身推导：中心线采样点、路段矩形中心、岔路确认线中点、门口两侧。
## 门一律视为已打开（探针不生成门体）；关门状态的阻挡由 breakable_gate_assert.gd 负责。
## 用法：godot --headless --path . --script res://tools/gauntlet_reachability_assert.gd

const LayoutProbe: GDScript = preload("res://tools/layout_probe.gd")

## 待检查的五关
const LEVEL_PATHS: Array[String] = [
	"res://levels/level_1.tres",
	"res://levels/level_2.tres",
	"res://levels/level_3.tres",
	"res://levels/level_4.tres",
	"res://levels/level_5.tres",
]

## 中心线点允许的落点误差（格）：走廊边缘附近的点容忍轻微内缩
const NEAR_CELLS: int = 6

var _failed: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for path: String in LEVEL_PATHS:
		_check_level(path)
	if _failed:
		quit(1)
		return
	print("gauntlet_reachability OK for %d levels" % LEVEL_PATHS.size())
	quit(0)

func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)
	printerr("[FAIL] %s" % msg)

func _check_level(path: String) -> void:
	var def: LevelDef = load(path) as LevelDef
	if def == null:
		_fail("%s 载入失败" % path)
		return
	var holder: Node2D = Node2D.new()
	root.add_child(holder)
	var probe: RefCounted = LayoutProbe.new()
	probe.call("build", def, holder)

	# 防"假通过"：布局必须真的有封死区，否则 BFS 会无条件成功
	var total: int = int(probe.get("grid_w")) * int(probe.get("grid_h"))
	var reachable: int = int(probe.call("reachable_cells"))
	if total <= 0 or reachable <= 0:
		_fail("%s 探针没造出可行域（total=%d reach=%d）" % [path, total, reachable])
		holder.queue_free()
		return
	if reachable >= total - 64:
		_fail("%s 几乎全图可达，障碍收集大概率失败" % path)
		holder.queue_free()
		return

	if not bool(probe.call("is_free", def.spawn_point)):
		_fail("%s 出生点被堵：%s" % [path, def.spawn_point])
	if not bool(probe.call("is_reachable", def.goal_point)):
		_fail("%s 出生点走不到终点：%s" % [path, def.goal_point])

	for i: int in def.route_centerline.size():
		var p: Vector2 = def.route_centerline[i]
		if not bool(probe.call("reachable_near", p, NEAR_CELLS)):
			_fail("%s 中心线第 %d 点不可达：%s" % [path, i, p])
	for seg: SegmentDef in def.segments:
		var center: Vector2 = seg.rect_position + seg.rect_size * 0.5
		if not bool(probe.call("reachable_near", center, NEAR_CELLS)):
			_fail("%s 路段 %s 中心不可达：%s" % [path, seg.segment_id, center])
	for fork: ChoiceForkDef in def.choice_forks:
		var probes: Dictionary[String, Vector2] = {
			"approach": fork.approach_rect_position + fork.approach_rect_size * 0.5,
			"commit_a": (fork.commit_a_from + fork.commit_a_to) * 0.5,
			"commit_b": (fork.commit_b_from + fork.commit_b_to) * 0.5,
		}
		for key: String in probes:
			if not bool(probe.call("reachable_near", probes[key], NEAR_CELLS)):
				_fail("%s 岔路 %s 的 %s 不可达：%s" % [path, fork.fork_id, key, probes[key]])
	for gate: GateDef in def.gates:
		# 门两侧各退 1.5 倍球径，确认门开着时前后都在同一连通域
		var step: Vector2 = gate.normal.normalized() * 66.0
		if not bool(probe.call("reachable_near", gate.position - step, NEAR_CELLS)):
			_fail("%s 门 %s 前侧不可达：%s" % [path, gate.gate_id, gate.position - step])
		if not bool(probe.call("reachable_near", gate.position + step, NEAR_CELLS)):
			_fail("%s 门 %s 后侧不可达：%s" % [path, gate.gate_id, gate.position + step])

	holder.queue_free()
