extends SceneTree
## 可撞门专项断言：双人满推可开 Gate1；单人/反向不能开；成败均不扣血。
## 用法：godot --headless --path . --script res://tools/breakable_gate_assert.gd
##
## 注意：--script 模式下脚本解析发生在 autoload 注册之前，所以本文件不能在解析期
## 引用任何依赖 autoload 的类（PixelBall / BreakableGate / BallHealth 等）——
## 一律用 Node + call/get/set，并在 _run() 里 load()，否则整条依赖链编译失败、
## 断言会"假通过"或直接挂死。

var _failed: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var input_hub: Node = root.get_node("InputHub")
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)
	input_hub.call("join_slot", 1, 2)
	input_hub.set("input_frozen", false)
	input_hub.call("reset_gains")
	game_state.set("protocol_version", "pilot-1.0")
	game_state.set("participant_a_slot", 0)
	game_state.set("current_level", load("res://levels/level_1.tres"))

	var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	await process_frame

	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()
	input_hub.set("input_frozen", false)

	var gates: Array = level.get("_gates") as Array
	if gates.size() != 3:
		_fail("expected 3 gates, got %d" % gates.size())
		_finish()
		return
	var gate1: Node = gates[0] as Node
	_expect(gate1 != null and gate1.is_in_group("breakable_gate"),
		"gate must be in breakable_gate group")

	var ball: Node2D = level.get("_ball") as Node2D
	var health_state: Object = level.get("_state")
	if ball == null or health_state == null:
		_fail("level did not spawn ball/state")
		_finish()
		return
	var hp_before: float = float(health_state.get("hp"))
	var speed_before_fail: float = 200.0

	# 物理真撞：不能直接 call _evaluate_attempt。absorbent 门会吃掉当前速度，
	# 必须靠撞前速度把失败半开动画跑起来。
	_fill_gate_history(gate1, Vector2(8.0, 0.0), Vector2.ZERO, 12)
	gate1.set("_in_contact", false)
	gate1.set("_approach_speed", 0.0)
	ball.global_position = gate1.get("global_position") as Vector2 - Vector2(90.0, 0.0)
	ball.set("linear_velocity", Vector2(speed_before_fail, 0.0))
	# 瞬间赋速会被冲击判定当成 |Δv| 冲击（假冲击），把上一帧速度对齐掉
	ball.set("_prev_velocity", Vector2(speed_before_fail, 0.0))
	var saw_fail_motion: bool = false
	for _i: int in 48:
		_fill_gate_history(gate1, Vector2(8.0, 0.0), Vector2.ZERO, 12)
		await physics_frame
		var left_panel: Node2D = gate1.get("_panel_left") as Node2D
		var fail_tw: Tween = gate1.get("_fail_tween") as Tween
		if left_panel != null and absf(left_panel.rotation) > 0.02:
			saw_fail_motion = true
			break
		if fail_tw != null and fail_tw.is_valid() and fail_tw.is_running():
			saw_fail_motion = true
			break
	_expect(saw_fail_motion, "failed impact must play a visible half-open tween")
	_expect(not bool(gate1.call("is_opened")), "solo push must not open gate1")
	var velocity: Vector2 = ball.get("linear_velocity") as Vector2
	var away_speed: float = -velocity.dot(Vector2.RIGHT)
	_expect(away_speed <= 40.0, "failed gate must not fling the ball, away=%.1f" % away_speed)
	_expect(velocity.length() < speed_before_fail, "failed gate should kill incoming speed")

	# 真撞一次之后血量必须原样
	var hp_after_impact: float = float(health_state.get("hp"))
	_expect(is_equal_approx(hp_before, hp_after_impact),
		"physical gate impact must not damage, %.2f -> %.2f" % [hp_before, hp_after_impact])

	# 门冲击即使强度很高也不能扣血
	var health: Node = ball.get_node_or_null("BallHealth")
	if health == null:
		_fail("BallHealth missing")
		_finish()
		return
	var ball_consts: Dictionary = (ball.get_script() as GDScript).get_script_constant_map()
	health.call("_on_impacted", 240.0, str(ball_consts["COLLISION_GATE"]))
	_expect(is_equal_approx(hp_after_impact, float(health_state.get("hp"))),
		"gate collision must never deal damage")

	# 反向输入：不能开
	_fill_gate_history(gate1, Vector2(8.0, 0.0), Vector2(-8.0, 0.0), 12)
	gate1.set("_in_contact", false)
	gate1.call("_evaluate_attempt", Vector2.RIGHT)
	_expect(not bool(gate1.call("is_opened")), "opposite push must not open gate1")

	# 双人同向满推且速度过门槛：应打开
	ball.set("linear_velocity", Vector2(320.0, 0.0))
	_fill_gate_history(gate1, Vector2(8.0, 0.0), Vector2(8.0, 0.0), 16)
	gate1.set("_in_contact", false)
	gate1.call("_evaluate_attempt", Vector2.RIGHT)
	_expect(bool(gate1.call("is_opened")), "coop full push should open gate1")
	# 碰撞体是 set_deferred 关掉的，等一帧再查
	await process_frame
	var shape: CollisionShape2D = gate1.get("_shape") as CollisionShape2D
	_expect(shape != null and shape.disabled, "opened gate collision must disable")
	_expect(is_equal_approx(hp_after_impact, float(health_state.get("hp"))),
		"gate attempts must not deal damage")

	# 从右往左撞：同一扇门（normal=+X）被反向撞时也要能开，动画方向要跟着翻
	var gate3: Node = gates[2] as Node
	var gate3_pos: Vector2 = gate3.get("global_position") as Vector2
	var reverse_speed: float = 380.0
	ball.global_position = gate3_pos + Vector2(90.0, 0.0)
	ball.set("linear_velocity", Vector2(-reverse_speed, 0.0))
	ball.set("_prev_velocity", Vector2(-reverse_speed, 0.0))
	gate3.set("_in_contact", false)
	gate3.set("_approach_speed", 0.0)
	gate3.set("_approach_dir", Vector2.ZERO)
	for _i: int in 48:
		# 双方都朝 -X 发力，方向与穿门方向一致
		_fill_gate_history(gate3, Vector2(-8.0, 0.0), Vector2(-8.0, 0.0), 16)
		await physics_frame
		if bool(gate3.call("is_opened")):
			break
	_expect(bool(gate3.call("is_opened")), "coop push must open gate3 when hit right-to-left")
	var pass_dir: Vector2 = gate3.get("_pass_dir") as Vector2
	_expect(pass_dir.x < 0.0,
		"reverse hit must resolve a leftward pass dir, got %s" % pass_dir)
	_expect(str(gate3.call("_pass_dir_label")) == "R2L",
		"reverse hit must log dir=R2L, got %s" % gate3.call("_pass_dir_label"))
	# 门叶倒下方向必须镜像：sx<0 时上扇转角为正
	var upper: Node2D = gate3.get("_panel_left") as Node2D
	await process_frame
	await process_frame
	_expect(upper != null and upper.rotation > 0.0,
		"panels must fall away from the ball when hit right-to-left, rot=%.3f"
			% (upper.rotation if upper != null else 0.0))
	_expect(float((ball.get("linear_velocity") as Vector2).x) < 0.0,
		"ball must keep heading left after breaking through")
	_expect(is_equal_approx(hp_after_impact, float(health_state.get("hp"))),
		"reverse gate break must not deal damage")

	# 普通障碍仍带 ordinary_obstacle 分组
	# SplitScreen 会把 World 挪进 SubViewport，不能按 level 的直接子节点找
	var world: Node2D = level.find_child("World", true, false) as Node2D
	if world == null:
		_fail("World node missing")
		_finish()
		return
	var found_ordinary: bool = false
	for child: Node in world.get_children():
		if child.is_in_group("ordinary_obstacle"):
			found_ordinary = true
			break
	_expect(found_ordinary, "ordinary obstacles must remain damageable")

	level.queue_free()
	await process_frame
	await _assert_hard_gate_runup(input_hub, game_state)

	_finish()

## 第 3/5 关的门统一用第 1 关最难那档（300 px/s、余弦 0.84、有效发力 0.75）。
## 这一档必须"跑得起来"：双人满推从出生点冲到门口时，正向速度要过阈值并真的撞开门。
## 阈值调高但助跑距离不够的话，玩家会卡死在门前，所以这条必须端到端跑一遍。
func _assert_hard_gate_runup(input_hub: Node, game_state: Node) -> void:
	for level_path: String in ["res://levels/level_3.tres", "res://levels/level_5.tres"]:
		var level_def: Resource = load(level_path)
		game_state.set("current_level", level_def)
		var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		var intro: Node = level.find_child("IntroPopup", true, false)
		if intro != null:
			intro.queue_free()
		input_hub.set("input_frozen", false)

		var gates: Array = level.get("_gates") as Array
		if gates.is_empty():
			_fail("%s should spawn gates" % level_path)
			level.queue_free()
			await process_frame
			continue
		for gate: Node in gates:
			var gate_def: Resource = gate.get("def") as Resource
			_expect(
				is_equal_approx(float(gate_def.get("speed_threshold")), 300.0),
				"%s %s must use the hard threshold, got %.0f"
					% [level_path, gate_def.get("gate_id"), gate_def.get("speed_threshold")]
			)
			_expect(
				is_equal_approx(float(gate_def.get("direction_cosine_min")), 0.84)
				and is_equal_approx(float(gate_def.get("activity_ratio_min")), 0.75),
				"%s %s must use the hard cosine/activity pair" % [level_path, gate_def.get("gate_id")]
			)

		# 只测第一扇门：它离出生点最近，助跑距离最短，是最容易卡住的那扇
		var gate1: Node = gates[0] as Node
		var ball: Node2D = level.get("_ball") as Node2D
		var gate_pos: Vector2 = gate1.get("global_position") as Vector2
		# 把球挪到门前一段直线助跑距离外，正对门轴推
		var axis: Vector2 = ((gate1.get("def") as Resource).get("normal") as Vector2).normalized()
		var pass_dir: Vector2 = axis if (gate_pos - ball.global_position).dot(axis) > 0.0 else -axis
		ball.global_position = gate_pos - pass_dir * 420.0
		ball.set("linear_velocity", Vector2.ZERO)
		ball.set("_prev_velocity", Vector2.ZERO)
		await physics_frame

		var press_x: StringName = "p1_right" if pass_dir.x > 0.0 else "p1_left"
		var press_x2: StringName = "p2_right" if pass_dir.x > 0.0 else "p2_left"
		Input.action_press(press_x)
		Input.action_press(press_x2)
		var peak: float = 0.0
		for _i: int in 240:
			await physics_frame
			peak = maxf(peak, (ball.get("linear_velocity") as Vector2).dot(pass_dir))
			if bool(gate1.call("is_opened")):
				break
		Input.action_release(press_x)
		Input.action_release(press_x2)
		_expect(
			bool(gate1.call("is_opened")),
			"%s first hard gate must break with a 420px run-up, peak=%.0f px/s"
				% [level_path, peak]
		)
		_expect(
			peak >= 300.0,
			"%s run-up peaked below the hard threshold: %.0f px/s" % [level_path, peak]
		)
		print("  %s run-up peak %.0f px/s" % [level_path, peak])
		level.queue_free()
		await process_frame

## 记一个失败（不抛断言：--script 模式下断言中断会让进程挂死）
func _fail(msg: String) -> void:
	_failed = true
	printerr("[FAIL] %s" % msg)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("breakable_gate_assert OK")
	quit(0)

## 向门写入一段力历史，模拟判定窗口
func _fill_gate_history(gate: Node, force_a: Vector2, force_b: Vector2, count: int) -> void:
	var history: Array[Dictionary] = []
	var now_us: int = Time.get_ticks_usec()
	for i: int in count:
		history.append({
			"t_us": now_us - (count - i) * 20_000,
			"a": force_a,
			"b": force_b,
		})
	gate.set("_force_history", history)
