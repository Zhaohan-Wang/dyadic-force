extends SceneTree
## 协作物理回归：单人无法稳定起步、双人同向可启动、失配降效并产旋、松手保留惯性。
## 用法：godot --headless --path . --script res://tools/coop_physics_assert.gd

var _failed: int = 0
var _passed: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var input_hub: Node = root.get_node("InputHub")
	game_state.set("current_level", load("res://levels/practice.tres"))
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)  # KEYBOARD_WASD
	input_hub.call("join_slot", 1, 2)  # KEYBOARD_ARROWS
	input_hub.set("input_frozen", false)
	input_hub.call("reset_gains")

	var packed: PackedScene = load("res://scenes/level.tscn") as PackedScene
	var level: Node = packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	input_hub.set("input_frozen", false)
	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()

	var ball: RigidBody2D = level.find_child("Ball", true, false) as RigidBody2D
	if ball == null:
		push_error("coop_physics_assert: Ball node not found")
		quit(1)
		return

	# 缩短输入建立时间，使断言聚焦物理而非滤波时长
	ball.set("input_rise_digital", 0.02)
	ball.set("input_rise_joy", 0.02)
	ball.set("input_release", 0.02)
	ball.freeze = false
	ball.sleeping = false
	var home: Vector2 = ball.global_position

	await _assert_solo_cannot_start(ball, input_hub, home)
	await _assert_duo_aligned_starts(ball, input_hub, home)
	await _assert_duo_70_starts(ball, input_hub, home)
	await _assert_mismatch_spins(ball, input_hub, home)
	await _assert_coast_inertia(ball, input_hub, home)

	print("COOP_PHYSICS_ASSERT passed=%d failed=%d" % [_passed, _failed])
	quit(_failed)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  OK  ", name, " ", detail)
	else:
		_failed += 1
		print("  FAIL ", name, " ", detail)

func _reset_ball(ball: RigidBody2D, home: Vector2) -> void:
	ball.global_position = home
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	ball.rotation = 0.0
	ball.sleeping = false
	ball.freeze = false

func _release_all() -> void:
	for action: String in [
		"p1_left", "p1_right", "p1_up", "p1_down",
		"p2_left", "p2_right", "p2_up", "p2_down",
	]:
		Input.action_release(action)

func _await_physics(frames: int) -> void:
	for _i: int in frames:
		await physics_frame

func _assert_solo_cannot_start(ball: RigidBody2D, input_hub: Node, home: Vector2) -> void:
	input_hub.call("reset_gains")
	_reset_ball(ball, home)
	_release_all()
	await _await_physics(4)
	var start: Vector2 = ball.global_position
	for _i: int in 90:
		Input.action_press("p1_right")
		await physics_frame
	_release_all()
	var speed: float = ball.linear_velocity.length()
	var travel: float = ball.global_position.distance_to(start)
	_check(
		"solo cannot stably start",
		speed < 12.0 and travel < 6.0,
		"speed=%.2f travel=%.2f" % [speed, travel]
	)
	_reset_ball(ball, home)
	await _await_physics(8)

func _assert_duo_aligned_starts(ball: RigidBody2D, input_hub: Node, home: Vector2) -> void:
	input_hub.call("reset_gains")
	_reset_ball(ball, home)
	_release_all()
	await _await_physics(4)
	var start: Vector2 = ball.global_position
	for _i: int in 50:
		Input.action_press("p1_right")
		Input.action_press("p2_right")
		await physics_frame
	var speed: float = ball.linear_velocity.length()
	var travel: float = ball.global_position.distance_to(start)
	var slip: float = float(ball.get("last_slip"))
	_check(
		"duo aligned starts",
		speed > 50.0 and travel > 12.0,
		"speed=%.2f travel=%.2f slip=%.2f" % [speed, travel, slip]
	)
	_check("duo aligned low slip", slip < 0.25, "slip=%.2f" % slip)
	_release_all()
	_reset_ball(ball, home)
	await _await_physics(8)

func _assert_duo_70_starts(ball: RigidBody2D, input_hub: Node, home: Vector2) -> void:
	input_hub.set("slot_gains", [0.70, 0.70])
	_reset_ball(ball, home)
	_release_all()
	await _await_physics(4)
	var start: Vector2 = ball.global_position
	for _i: int in 70:
		Input.action_press("p1_right")
		Input.action_press("p2_right")
		await physics_frame
	var speed: float = ball.linear_velocity.length()
	var travel: float = ball.global_position.distance_to(start)
	_check(
		"duo 70% aligned starts",
		speed > 35.0 and travel > 8.0,
		"speed=%.2f travel=%.2f" % [speed, travel]
	)
	_release_all()
	input_hub.call("reset_gains")
	_reset_ball(ball, home)
	await _await_physics(8)

func _assert_mismatch_spins(ball: RigidBody2D, input_hub: Node, home: Vector2) -> void:
	input_hub.call("reset_gains")
	_reset_ball(ball, home)
	_release_all()
	await _await_physics(4)
	var start: Vector2 = ball.global_position
	var max_omega: float = 0.0
	var max_slip: float = 0.0
	for _i: int in 60:
		Input.action_press("p1_right")
		Input.action_press("p2_left")
		await physics_frame
		max_omega = maxf(max_omega, absf(ball.angular_velocity))
		max_slip = maxf(max_slip, float(ball.get("last_slip")))
	var travel: float = ball.global_position.distance_to(start)
	var speed: float = ball.linear_velocity.length()
	_check("mismatch produces spin", max_omega > 2.5, "omega=%.2f" % max_omega)
	_check("mismatch high slip", max_slip > 0.7, "slip=%.2f" % max_slip)
	_check(
		"mismatch low translation",
		speed < 40.0 and travel < 20.0,
		"speed=%.2f travel=%.2f" % [speed, travel]
	)
	_release_all()
	_reset_ball(ball, home)
	await _await_physics(8)

func _assert_coast_inertia(ball: RigidBody2D, input_hub: Node, home: Vector2) -> void:
	input_hub.call("reset_gains")
	_reset_ball(ball, home)
	_release_all()
	await _await_physics(4)
	for _i: int in 45:
		Input.action_press("p1_right")
		Input.action_press("p2_right")
		await physics_frame
	var speed_after_push: float = ball.linear_velocity.length()
	_release_all()
	await _await_physics(3)
	var speed_early: float = ball.linear_velocity.length()
	await _await_physics(45)
	var speed_late: float = ball.linear_velocity.length()
	_check("coast retains inertia", speed_after_push > 50.0 and speed_early > 25.0,
		"push=%.1f early=%.1f" % [speed_after_push, speed_early])
	_check(
		"coast decays predictably",
		speed_late < speed_early and speed_late > 0.5,
		"early=%.1f late=%.1f" % [speed_early, speed_late]
	)
	_release_all()
	_reset_ball(ball, home)
