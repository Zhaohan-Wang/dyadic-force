class_name ChoiceForkTracker
extends RefCounted
## 第 5 关隐藏岔路追踪：持续输入偏好、冲突、提交与反转。

var _forks: Array[ChoiceForkDef] = []
var _ball: PixelBall = null
## fork_id -> 运行时状态字典
var _states: Dictionary = {}
var _active_choice_id: String = ""
var _current_branch: String = ""

const PREFERENCE_HOLD_S: float = 0.18
const PREFERENCE_FORCE_MIN: float = 0.40

func setup(forks: Array[ChoiceForkDef], ball: PixelBall) -> void:
	_forks = forks
	_ball = ball
	_states.clear()
	_active_choice_id = ""
	_current_branch = ""
	for fork: ChoiceForkDef in _forks:
		_states[fork.fork_id] = {
			"started": false,
			"pref_a": "",
			"pref_b": "",
			"conflict": false,
			"committed": "",
			"a_hold": 0.0,
			"b_hold": 0.0,
			"a_dir_acc": Vector2.ZERO,
			"b_dir_acc": Vector2.ZERO,
			"conflict_ms": 0.0,
			"first_changer": "",
		}

func update(delta: float) -> void:
	if _ball == null:
		return
	for fork: ChoiceForkDef in _forks:
		_update_fork(fork, delta)

func _update_fork(fork: ChoiceForkDef, delta: float) -> void:
	var st: Dictionary = _states[fork.fork_id] as Dictionary
	var pos: Vector2 = _ball.global_position
	var in_approach: bool = fork.approach_rect().has_point(pos)
	if in_approach and not bool(st["started"]):
		st["started"] = true
		_active_choice_id = fork.fork_id
		ExperimentLog.log_event("choice_started", {
			"component_id": fork.fork_id,
			"core_x": pos.x,
			"core_y": pos.y,
		})
	if not bool(st["started"]):
		return
	if str(st["committed"]) == "":
		_update_preferences(fork, st, delta)
	_update_commit(fork, st, pos)

func _update_preferences(fork: ChoiceForkDef, st: Dictionary, delta: float) -> void:
	var slot_a: int = GameState.participant_a_slot
	var slot_b: int = 1 - slot_a
	var fa: ForceMapper.Sample = InputHub.get_force_sample(slot_a)
	var fb: ForceMapper.Sample = InputHub.get_force_sample(slot_b)
	var dir_a: String = _project_branch(fork, fa.force)
	var dir_b: String = _project_branch(fork, fb.force)

	if dir_a != "":
		st["a_hold"] = float(st["a_hold"]) + delta
		st["a_dir_acc"] = (st["a_dir_acc"] as Vector2) + fa.force
	else:
		st["a_hold"] = 0.0
		st["a_dir_acc"] = Vector2.ZERO
	if dir_b != "":
		st["b_hold"] = float(st["b_hold"]) + delta
		st["b_dir_acc"] = (st["b_dir_acc"] as Vector2) + fb.force
	else:
		st["b_hold"] = 0.0
		st["b_dir_acc"] = Vector2.ZERO

	if str(st["pref_a"]) == "" and float(st["a_hold"]) >= PREFERENCE_HOLD_S:
		var pref: String = _project_branch(fork, st["a_dir_acc"] as Vector2)
		if pref != "":
			st["pref_a"] = pref
			ExperimentLog.log_event("choice_preference_A", {
				"component_id": fork.fork_id,
				"branch": pref,
				"core_x": _ball.global_position.x,
				"core_y": _ball.global_position.y,
			})
	if str(st["pref_b"]) == "" and float(st["b_hold"]) >= PREFERENCE_HOLD_S:
		var pref_b: String = _project_branch(fork, st["b_dir_acc"] as Vector2)
		if pref_b != "":
			st["pref_b"] = pref_b
			ExperimentLog.log_event("choice_preference_B", {
				"component_id": fork.fork_id,
				"branch": pref_b,
				"core_x": _ball.global_position.x,
				"core_y": _ball.global_position.y,
			})

	var pa: String = str(st["pref_a"])
	var pb: String = str(st["pref_b"])
	if pa != "" and pb != "" and pa != pb:
		if not bool(st["conflict"]):
			st["conflict"] = true
			ExperimentLog.log_event("choice_conflict", {
				"component_id": fork.fork_id,
				"note": "%s_vs_%s" % [pa, pb],
				"core_x": _ball.global_position.x,
				"core_y": _ball.global_position.y,
			})
		st["conflict_ms"] = float(st["conflict_ms"]) + delta * 1000.0
		# 谁先改变：若当前持续输入与初始偏好不同
		if str(st["first_changer"]) == "":
			if dir_a != "" and dir_a != pa:
				st["first_changer"] = "A"
			elif dir_b != "" and dir_b != pb:
				st["first_changer"] = "B"

func _project_branch(fork: ChoiceForkDef, force: Vector2) -> String:
	if force.length() < PREFERENCE_FORCE_MIN:
		return ""
	var da: Vector2 = fork.branch_a_direction.normalized()
	var db: Vector2 = fork.branch_b_direction.normalized()
	var proj_a: float = force.normalized().dot(da)
	var proj_b: float = force.normalized().dot(db)
	if proj_a < 0.35 and proj_b < 0.35:
		return ""
	if proj_a >= proj_b:
		return fork.branch_a_label
	return fork.branch_b_label

func _update_commit(fork: ChoiceForkDef, st: Dictionary, pos: Vector2) -> void:
	var hit_a: bool = _crossed_line(fork.commit_a_from, fork.commit_a_to, pos)
	var hit_b: bool = _crossed_line(fork.commit_b_from, fork.commit_b_to, pos)
	var branch: String = ""
	if hit_a:
		branch = fork.branch_a_label
	elif hit_b:
		branch = fork.branch_b_label
	else:
		# 若已提交后又退回另一支
		return
	var prev: String = str(st["committed"])
	if prev == "":
		st["committed"] = branch
		_current_branch = branch
		_active_choice_id = fork.fork_id
		ExperimentLog.log_event("branch_committed", {
			"component_id": fork.fork_id,
			"branch": branch,
			"core_x": pos.x,
			"core_y": pos.y,
		})
	elif prev != branch:
		st["committed"] = branch
		_current_branch = branch
		ExperimentLog.log_event("branch_reversal", {
			"component_id": fork.fork_id,
			"branch": branch,
			"note": "from_%s" % prev,
			"core_x": pos.x,
			"core_y": pos.y,
		})

## 球心是否靠近确认线段（距离阈值内）
func _crossed_line(from: Vector2, to: Vector2, pos: Vector2) -> bool:
	var ab: Vector2 = to - from
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001:
		return pos.distance_to(from) < 28.0
	var t: float = clampf((pos - from).dot(ab) / len_sq, 0.0, 1.0)
	var nearest: Vector2 = from + ab * t
	return pos.distance_to(nearest) <= 36.0

func get_active_choice_id() -> String:
	return _active_choice_id

func get_current_branch() -> String:
	return _current_branch
