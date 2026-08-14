class_name PerturbationController
extends RefCounted
## 隐藏失衡控制器：在候选路段内按可复现序列触发真实/假扰动。

signal perturb_changed(active: bool, slot: int, gain: float)

var _def: LevelDef
var _ball: PixelBall = null
var _zones_by_id: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sequence: Array[int] = []
var _sequence_index: int = 0
var _triggered_count: int = 0
var _active: bool = false
var _active_slot: int = -1
var _active_gain: float = 1.0
## 本次扰动施加的侧偏角（度，带符号；0 表示只衰减幅值）
var _active_lateral_deg: float = 0.0
var _active_left: float = 0.0
var _gap_left: float = 0.0
var _visited_candidates: Dictionary = {}
var _is_sham: bool = false
var _recent_collision_s: float = 999.0
var _recent_respawn_s: float = 999.0
var _enabled: bool = false

func setup(def: LevelDef, ball: PixelBall, zones: Array[RouteSegmentZone]) -> void:
	_def = def
	_ball = ball
	_zones_by_id.clear()
	for zone: RouteSegmentZone in zones:
		if zone.def != null and zone.def.segment_type == "perturb_candidate":
			_zones_by_id[zone.def.segment_id] = zone
	_enabled = (
		_def != null
		and not _def.perturb_candidate_ids.is_empty()
		and _def.challenge_type == "imbalance"
	)
	_rng.seed = _def.perturb_sequence_seed if _def != null else 0
	_build_sequence()
	_reset_runtime()

func _build_sequence() -> void:
	_sequence.clear()
	# 平衡 A/B：按种子决定先扰谁，其后交替。连续模式按目标次数铺满整关。
	var count: int = maxi(_def.perturb_target_count, 2)
	var first: int = _rng.randi_range(0, 1)
	for i: int in count:
		_sequence.append(first if (i % 2 == 0) else 1 - first)

func _is_continuous() -> bool:
	return _def != null and _def.perturb_continuous

func _reset_runtime() -> void:
	_sequence_index = 0
	_triggered_count = 0
	_active = false
	_active_slot = -1
	_active_gain = 1.0
	_active_left = 0.0
	_gap_left = 0.0
	_visited_candidates.clear()
	_is_sham = false
	InputHub.reset_gains()

func notify_collision() -> void:
	_recent_collision_s = 0.0

func notify_respawn() -> void:
	_recent_respawn_s = 0.0
	clear_active("respawn")

func clear_active(note: String = "cleared") -> void:
	if not _active:
		InputHub.reset_gains()
		perturb_changed.emit(false, -1, 1.0)
		return
	var was_slot: int = _active_slot
	var was_gain: float = _active_gain
	var was_lateral: float = _active_lateral_deg
	_active = false
	_active_slot = -1
	_active_gain = 1.0
	_active_lateral_deg = 0.0
	_active_left = 0.0
	InputHub.reset_gains()
	if not _is_sham:
		ExperimentLog.log_event("perturb_off", {
			"slot": was_slot,
			"gain": was_gain,
			"note": "%s lateral=%.1fdeg" % [note, was_lateral],
			"sequence_version": _def.perturb_sequence_version,
		})
	perturb_changed.emit(false, -1, 1.0)
	_is_sham = false

func update(delta: float, phase_running: bool) -> void:
	if not _enabled or _def == null or _ball == null:
		return
	_recent_collision_s += delta
	_recent_respawn_s += delta
	if _gap_left > 0.0:
		_gap_left = maxf(0.0, _gap_left - delta)
	if _active:
		_active_left -= delta
		if _active_left <= 0.0:
			clear_active("duration_end")
			_gap_left = _def.perturb_min_gap_s
		return
	if not phase_running:
		return
	if _triggered_count >= _sequence.size():
		return
	if _gap_left > 0.0:
		return
	_try_trigger()

func _try_trigger() -> void:
	# 连续模式：开局就扰，按时间循环，不等人走进三个候选框
	if _is_continuous():
		if _recent_respawn_s < 0.8:
			return
		_fire_next()
		return
	for cand_id: String in _def.perturb_candidate_ids:
		if _visited_candidates.has(cand_id):
			continue
		var zone: RouteSegmentZone = _zones_by_id.get(cand_id) as RouteSegmentZone
		if zone == null or not zone.contains_ball():
			continue
		var skip: String = _stability_skip_reason()
		if skip != "":
			ExperimentLog.log_event("perturb_skipped", {
				"segment_id": cand_id,
				"component_id": cand_id,
				"result_reason": skip,
				"sequence_version": _def.perturb_sequence_version,
				"core_x": _ball.global_position.x,
				"core_y": _ball.global_position.y,
			})
			# 不合格不标记 visited，允许路段内稍后重试；危险则本段跳过
			if skip == "recent_collision" or skip == "recent_respawn":
				_visited_candidates[cand_id] = true
			return
		_fire_at_candidate(cand_id)
		return

func _stability_skip_reason() -> String:
	if _recent_collision_s < 1.2:
		return "recent_collision"
	if _recent_respawn_s < 2.0:
		return "recent_respawn"
	var speed: float = _ball.linear_velocity.length()
	if speed < 40.0 or speed > 420.0:
		return "speed_out_of_range"
	var fa: ForceMapper.Sample = InputHub.get_force_sample(0)
	var fb: ForceMapper.Sample = InputHub.get_force_sample(1)
	if fa.force.length() < 0.25 or fb.force.length() < 0.25:
		return "low_activity"
	return ""

## 按序列打出下一次扰动。连续模式没有「当前路段」时，轮换候选 ID 只为日志可复算。
func _fire_next() -> void:
	var cand_id: String = "continuous"
	if not _def.perturb_candidate_ids.is_empty():
		cand_id = _def.perturb_candidate_ids[_triggered_count % _def.perturb_candidate_ids.size()]
	_fire_at_candidate(cand_id)

func _fire_at_candidate(cand_id: String) -> void:
	if _sequence.is_empty() or _triggered_count >= _sequence.size():
		return
	_visited_candidates[cand_id] = true
	ExperimentLog.log_event("perturb_candidate_enter", {
		"segment_id": cand_id,
		"component_id": cand_id,
		"sequence_version": _def.perturb_sequence_version,
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
	})
	var slot: int = _sequence[_sequence_index % _sequence.size()]
	_sequence_index += 1
	_triggered_count += 1
	var duration: float = _rng.randf_range(_def.perturb_duration_min_s, _def.perturb_duration_max_s)
	var gain: float = _rng.randf_range(_def.perturb_gain_min, _def.perturb_gain_max)
	# 侧偏方向按序列交替（种子可复现）：一次往一侧偏，下一次往另一侧
	var lateral_sign: float = 1.0 if _triggered_count % 2 == 1 else -1.0
	var lateral_deg: float = lateral_sign * _rng.randf_range(
		_def.perturb_lateral_deg_min, _def.perturb_lateral_deg_max
	)
	# 只有正式实验的基线条件才做假扰动。日常试玩必须真扰，
	# 否则第四关从头到尾都没有手感，计时器上的「干扰」灯也对不上。
	var is_baseline: bool = (
		GameState.experiment_mode
		and GameState.experiment_condition != "perturbation"
	)
	_active = true
	_active_slot = slot
	_active_gain = gain
	_active_lateral_deg = lateral_deg
	_active_left = duration
	_is_sham = is_baseline
	if is_baseline:
		InputHub.reset_gains()
		ExperimentLog.log_event("sham_perturbation", {
			"slot": slot,
			"gain": 1.0,
			"segment_id": cand_id,
			"component_id": cand_id,
			"sequence_version": _def.perturb_sequence_version,
			"note": "duration=%.2f lateral=%.1fdeg" % [duration, lateral_deg],
			"core_x": _ball.global_position.x,
			"core_y": _ball.global_position.y,
		})
		perturb_changed.emit(false, -1, 1.0)
	else:
		InputHub.slot_gains[0] = gain if slot == 0 else 1.0
		InputHub.slot_gains[1] = gain if slot == 1 else 1.0
		var bias: float = deg_to_rad(lateral_deg)
		InputHub.slot_force_bias_rad[0] = bias if slot == 0 else 0.0
		InputHub.slot_force_bias_rad[1] = bias if slot == 1 else 0.0
		ExperimentLog.log_event("perturb_on", {
			"slot": slot,
			"gain": gain,
			"segment_id": cand_id,
			"component_id": cand_id,
			"sequence_version": _def.perturb_sequence_version,
			"note": "segment_trigger duration=%.2f lateral=%.1fdeg" % [duration, lateral_deg],
			"core_x": _ball.global_position.x,
			"core_y": _ball.global_position.y,
		})
		perturb_changed.emit(true, slot, gain)

func get_sequence_version() -> String:
	return _def.perturb_sequence_version if _def != null else ""
