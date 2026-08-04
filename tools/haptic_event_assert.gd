extends Node
## 实机确认：扣血震动 + 传送门渐强震。

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var devices: PackedInt32Array = Input.get_connected_joypads()
	if devices.is_empty():
		print("haptic_event_assert SKIP: no connected joypad")
		get_tree().quit(0)
		return

	var joy_id: int = devices[0]
	var previous_strength: float = GameState.haptic_strength
	GameState.haptic_strength = 1.0
	InputHub.clear_slots()
	InputHub.join_slot(0, InputHub.SourceKind.JOYPAD, joy_id)
	InputHub.input_frozen = false
	HapticHub.begin_level(null)

	HapticHub.pulse_damage(0.5)
	var small_hit: Vector2 = await _wait_vibration(joy_id, 0.70, 0.45)
	assert(small_hit.y >= 0.70, "half-heart must clear motor threshold, got %.2f" % small_hit.y)
	Input.stop_joy_vibration(joy_id)
	await get_tree().create_timer(0.18, true, false, true).timeout

	HapticHub.pulse_damage(1.5)
	var large_hit: Vector2 = await _wait_vibration(joy_id, 0.90, 0.45)
	assert(large_hit.y >= 0.90, "one-heart+ must rumble hard, got %.2f" % large_hit.y)
	Input.stop_joy_vibration(joy_id)
	await get_tree().create_timer(0.12, true, false, true).timeout

	# 传送门渐强：前段可感，后段接近满振
	HapticHub.play_teleport_rumble(0.70)
	await get_tree().create_timer(0.06, true, false, true).timeout
	var teleport_early: Vector2 = Input.get_joy_vibration_strength(joy_id)
	assert(teleport_early.y >= 0.30, "teleport start too weak: %.2f" % teleport_early.y)
	var teleport_late: Vector2 = await _wait_vibration(joy_id, 0.80, 0.75)
	assert(teleport_late.y >= 0.80, "teleport ramp should peak: %.2f" % teleport_late.y)

	HapticHub.end_level()
	GameState.haptic_strength = previous_strength
	print(
		"haptic_event_assert OK device=%d small=%.2f large=%.2f teleport=%.2f→%.2f"
		% [joy_id, small_hit.y, large_hit.y, teleport_early.y, teleport_late.y]
	)
	get_tree().quit(0)

func _wait_vibration(joy_id: int, min_strong: float, timeout_s: float) -> Vector2:
	var left: float = timeout_s
	var best: Vector2 = Vector2.ZERO
	while left > 0.0:
		var strength: Vector2 = Input.get_joy_vibration_strength(joy_id)
		if strength.y > best.y:
			best = strength
		if strength.y >= min_strong:
			return strength
		await get_tree().process_frame
		left -= get_process_delta_time()
	return best
