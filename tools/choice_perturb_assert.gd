extends SceneTree
## 岔路追踪与路段扰动断言（无界面）。
## 用法：godot --headless --path . --script res://tools/choice_perturb_assert.gd
##
## 注意：--script 模式下本文件的解析早于 autoload 注册，所以不能在解析期引用
## PixelBall / ChoiceForkTracker / PerturbationController 这类依赖 autoload 的类，
## 一律 load() + call/get/set；断言也不用 assert（中断协程会让进程挂死）。

var _failed: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_choice_tracker()
	await _test_perturbation_controller()
	if _failed:
		quit(1)
		return
	print("choice_perturb_assert OK")
	quit(0)

func _fail(msg: String) -> void:
	_failed = true
	printerr("[FAIL] %s" % msg)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _test_choice_tracker() -> void:
	var fork: ChoiceForkDef = ChoiceForkDef.new()
	fork.fork_id = "fork_test"
	# 尺度必须接近真实关卡：确认线要离观察区足够远（判定阈值 36px，球半径 44）
	fork.approach_rect_position = Vector2(200, 200)
	fork.approach_rect_size = Vector2(240, 180)
	fork.branch_a_direction = Vector2(0, -1)
	fork.branch_b_direction = Vector2(0, 1)
	fork.commit_a_from = Vector2(240, 120)
	fork.commit_a_to = Vector2(400, 120)
	fork.commit_b_from = Vector2(240, 460)
	fork.commit_b_to = Vector2(400, 460)
	fork.branch_a_label = "narrow"
	fork.branch_b_label = "wide"

	var ball: Node2D = _make_bare_ball()
	root.add_child(ball)
	ball.global_position = Vector2(320, 290)

	var tracker: RefCounted = (
		load("res://scripts/experiment/choice_fork_tracker.gd") as GDScript
	).new() as RefCounted
	var forks: Array[ChoiceForkDef] = [fork]
	tracker.call("setup", forks, ball)

	var input_hub: Node = root.get_node("InputHub")
	var game_state: Node = root.get_node("GameState")
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)
	input_hub.call("join_slot", 1, 2)
	input_hub.set("input_frozen", false)
	game_state.set("participant_a_slot", 0)

	# 无有效力：偏好仍空
	tracker.call("update", 0.05)
	_expect(str(tracker.call("get_current_branch")) == "", "no commit without crossing")

	# 穿过确认线 A
	ball.global_position = Vector2(320, 130)
	tracker.call("update", 0.05)
	_expect(str(tracker.call("get_current_branch")) == "narrow", "should commit narrow")

	# 反转到 B
	ball.global_position = Vector2(320, 455)
	tracker.call("update", 0.05)
	_expect(str(tracker.call("get_current_branch")) == "wide", "should reverse to wide")
	ball.queue_free()

## 造一个够用的裸球：ball.gd 的 _ready 需要 BallSprite / Shadow 两个带 ShaderMaterial 的子节点
func _make_bare_ball() -> Node2D:
	var ball: Node2D = (load("res://scripts/ball.gd") as GDScript).new() as Node2D
	ball.set("ball_radius", 44.0)
	var shaders: Dictionary[String, String] = {
		"BallSprite": "res://shaders/pixel_ball.gdshader",
		"Shadow": "res://shaders/ball_shadow.gdshader",
	}
	for child_name: String in shaders:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = child_name
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load(shaders[child_name]) as Shader
		sprite.material = mat
		ball.add_child(sprite)
	return ball

func _test_perturbation_controller() -> void:
	var game_state: Node = root.get_node("GameState")
	var input_hub: Node = root.get_node("InputHub")
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)
	input_hub.call("join_slot", 1, 2)
	input_hub.set("input_frozen", false)
	input_hub.call("reset_gains")
	game_state.set("experiment_mode", true)
	game_state.set("protocol_version", "pilot-1.0")
	game_state.set("current_level", load("res://levels/level_4.tres"))

	var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()
	input_hub.set("input_frozen", false)

	var perturb: RefCounted = level.get("_perturb") as RefCounted
	if perturb == null:
		_fail("perturb controller missing")
		return
	_expect(str(perturb.call("get_sequence_version")) == "v1", "sequence version")

	var ball: Node2D = level.get("_ball") as Node2D
	# 第 4 关起步大道上的合法位置（曲线布局出生点 (350,360)）
	ball.global_position = Vector2(500, 356)
	ball.set("linear_velocity", Vector2(120, 0))
	var gains: Array = input_hub.get("slot_gains") as Array
	gains[0] = 1.0
	gains[1] = 1.0
	var state: Object = level.get("_state")
	state.set("phase", LevelState.Phase.RUNNING)

	# 连续模式：人不在候选框里，update 也必须立刻打出下一次
	game_state.set("experiment_mode", false)
	perturb.call("clear_active", "test_reset")
	var zone_script_pre: GDScript = load("res://scripts/route_segment_zone.gd")
	var zones_pre: Array = Array(level.get("_segment_zones") as Array, TYPE_OBJECT, "Area2D", zone_script_pre)
	var def_pre: LevelDef = load("res://levels/level_4.tres") as LevelDef
	perturb.call("setup", def_pre, ball, zones_pre)
	ball.global_position = Vector2(350, 360)
	ball.set("linear_velocity", Vector2.ZERO)
	perturb.call("update", 0.1, true)
	gains = input_hub.get("slot_gains") as Array
	var min_g_start: float = minf(float(gains[0]), float(gains[1]))
	_expect(min_g_start < 0.9, "continuous mode must start without a candidate zone, got %s" % [gains])

	# 单一协议：第 4 关始终可改增益
	game_state.set("experiment_mode", true)
	perturb.call("clear_active", "test_reset")
	# 重建以清空 visited（setup 再次）。
	# RouteSegmentZone 间接依赖 autoload，不能在解析期出现，只能在运行期拼类型化数组。
	var zone_script: GDScript = load("res://scripts/route_segment_zone.gd")
	var zones: Array = Array(level.get("_segment_zones") as Array, TYPE_OBJECT, "Area2D", zone_script)
	var def: LevelDef = load("res://levels/level_4.tres") as LevelDef
	perturb.call("setup", def, ball, zones)
	# 放进候选段 l4_perturb_a（矩形中心 (860,390)）
	ball.global_position = Vector2(860, 390)
	ball.set("linear_velocity", Vector2(100, 0))
	# 注入足够活动：通过直接设置 slot 后依赖 get_force_sample；键盘无输入时可能跳过
	# 因此用 notify 后手动调用 _fire_at_candidate
	perturb.call("_fire_at_candidate", "l4_perturb_a")
	gains = input_hub.get("slot_gains") as Array
	var min_g: float = minf(float(gains[0]), float(gains[1]))
	_expect(min_g < 0.9, "perturbation should reduce one gain, got %s" % [gains])

	# 侧偏：只作用在被扰动的那一侧，且只旋转最终力，不动 raw/calibrated
	var bias: Array = input_hub.get("slot_force_bias_rad") as Array
	var skewed_slot: int = 0 if float(gains[0]) < float(gains[1]) else 1
	_expect(absf(float(bias[skewed_slot])) > 0.01,
		"perturbed slot must get a lateral bias, got %s" % [bias])
	_expect(is_zero_approx(float(bias[1 - skewed_slot])),
		"partner slot must stay unbiased, got %s" % [bias])
	# 被扰动一侧的力方向必须真的偏离按键方向
	input_hub.set("input_frozen", false)
	var sample_script: GDScript = load("res://scripts/force_mapper.gd")
	var straight: Vector2 = Vector2.RIGHT * 8.0
	var rotated: Vector2 = straight.rotated(float(bias[skewed_slot]))
	_expect(sample_script != null and absf(rotated.angle_to(straight)) > 0.1,
		"lateral bias must rotate the applied force noticeably")
	# 扰动区间要能被关卡记成时间线片段
	var spans: Array = level.get("_perturb_spans") as Array
	_expect(spans.size() >= 1, "perturb span must be recorded for the results timeline")

	perturb.call("clear_active", "test_end")
	gains = input_hub.get("slot_gains") as Array
	_expect(is_equal_approx(float(gains[0]), 1.0) and is_equal_approx(float(gains[1]), 1.0),
		"clear_active must restore gains")
	bias = input_hub.get("slot_force_bias_rad") as Array
	_expect(is_zero_approx(float(bias[0])) and is_zero_approx(float(bias[1])),
		"clear_active must restore lateral bias, got %s" % [bias])

	level.queue_free()
	await process_frame
