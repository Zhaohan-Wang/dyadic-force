extends Node
## 实机确认：加入确认 + 扣血小震/大震（走 pulse_damage，含延迟时序）。

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

	HapticHub.confirm_join(-1)
	await get_tree().create_timer(0.20, true, false, true).timeout
	var join_strength: Vector2 = Input.get_joy_vibration_strength(joy_id)
	assert(join_strength.y >= 0.70, "join confirmation failed")
	Input.stop_joy_vibration(joy_id)
	await get_tree().create_timer(0.12, true, false, true).timeout

	InputHub.join_slot(0, InputHub.SourceKind.JOYPAD, joy_id)
	InputHub.input_frozen = false
	HapticHub.begin_level(null)

	HapticHub.pulse_damage(0.5)
	# pulse_damage 内部等两帧再下发
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var small_hit: Vector2 = Input.get_joy_vibration_strength(joy_id)
	assert(small_hit.y >= 0.70, "half-heart must clear motor threshold, got %.2f" % small_hit.y)
	Input.stop_joy_vibration(joy_id)
	await get_tree().create_timer(0.20, true, false, true).timeout

	HapticHub.pulse_damage(1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var large_hit: Vector2 = Input.get_joy_vibration_strength(joy_id)
	# 小震已抬到满强马达；大震用更长时长区分，二者 strong 均可顶满。
	assert(large_hit.y >= 0.90, "one-heart+ must rumble hard, got %.2f" % large_hit.y)

	HapticHub.end_level()
	GameState.haptic_strength = previous_strength
	print(
		"haptic_event_assert OK device=%d small=%.2f large=%.2f"
		% [joy_id, small_hit.y, large_hit.y]
	)
	get_tree().quit(0)
