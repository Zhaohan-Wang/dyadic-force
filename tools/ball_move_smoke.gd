extends SceneTree
## 关卡冒烟：双键盘同向满推若干物理帧后，球必须产生明显速度。

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

	# 分屏会把 World 挪进 Viewport，不能写死 Level/World/Ball。
	var ball: RigidBody2D = level.find_child("Ball", true, false) as RigidBody2D
	if ball == null:
		push_error("ball_move_smoke: Ball node not found")
		quit(1)
		return
	ball.freeze = false
	ball.sleeping = false
	var start_pos: Vector2 = ball.global_position

	for _i: int in 45:
		Input.action_press("p1_right")
		Input.action_press("p2_right")
		await physics_frame
	Input.action_release("p1_right")
	Input.action_release("p2_right")

	var speed: float = ball.linear_velocity.length()
	var travel: float = ball.global_position.distance_to(start_pos)
	print("ball_move_smoke speed=%.2f travel=%.2f pos=%s" % [speed, travel, ball.global_position])
	if speed < 40.0 and travel < 8.0:
		push_error("ball stayed nearly still under dual full push")
		quit(1)
		return
	print("ball_move_smoke OK")
	quit(0)
