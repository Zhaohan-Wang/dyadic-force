extends Node
## 把球砸向围墙：真实扣血后必须下发震动。

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.current_level = load("res://levels/practice.tres")
	GameState.haptic_strength = 1.0
	InputHub.clear_slots()
	InputHub.join_slot(0, InputHub.SourceKind.JOYPAD, 0)
	InputHub.join_slot(1, InputHub.SourceKind.KEYBOARD_ARROWS)
	InputHub.input_frozen = false

	var packed: PackedScene = load("res://scenes/level.tscn") as PackedScene
	var level: Node = packed.instantiate()
	get_tree().root.add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	InputHub.input_frozen = false
	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()
		await get_tree().process_frame

	var ball: RigidBody2D = level.find_child("Ball", true, false) as RigidBody2D
	assert(ball != null, "ball missing")
	var health: Node = ball.get_node_or_null("BallHealth")
	assert(health != null, "BallHealth missing")

	var hits: Array = []
	health.damaged.connect(func(amount: float, _hp: float) -> void:
		hits.append(amount)
	)

	ball.global_position = Vector2(180, 160)
	ball.linear_velocity = Vector2(-420, 0)
	ball.freeze = false

	for _i: int in 60:
		await get_tree().physics_frame
		if not hits.is_empty():
			# pulse_damage 会再等两帧
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			break

	assert(not hits.is_empty(), "wall hit produced no damage")
	assert(float(hits[0]) > 0.0, "damage must be positive")

	var pads: PackedInt32Array = Input.get_connected_joypads()
	if not pads.is_empty():
		var strength: Vector2 = Input.get_joy_vibration_strength(pads[0])
		assert(strength.y >= 0.45, "damage rumble missing after defer, got %.2f" % strength.y)

	print("haptic_collision_smoke OK damage=%.2f hits=%d" % [float(hits[0]), hits.size()])
	HapticHub.end_level()
	get_tree().quit(0)
