class_name ExperimentAnalyzer
extends RefCounted
## 只读取 raw CSV 的纯分析与结果导出；绝不回写原始日志。
## 默认只写 results/ 中有数据的表；人工复核走 export_review_package()。

const RESULT_FILES: PackedStringArray = [
	"trial_results.csv", "perturbation_results.csv", "gate_results.csv",
	"segment_results.csv", "choice_results.csv",
]
const QUIT_REASONS: PackedStringArray = [
	"level_select_requested", "level_tree_exit", "controller_disconnected",
]

const TRIAL_COLUMNS: PackedStringArray = [
	"analysis_version", "session_id", "trial_id", "station_id", "dyad_id",
	"participant_A", "participant_B", "relation_condition", "side_assignment",
	"level_id",
	"level_attempt_index", "protocol_version",
	"outcome", "quit_reason", "completion_time_ms",
	"perturbation_count", "perturbed_participants", "perturb_gain_mean",
	"perturb_first_onset_ms", "perturb_last_offset_ms",
	"compensation_valid_count", "compensation_reaction_median_ms",
	"recovery_recovered_count", "recovery_censored_count",
	"recovery_time_median_ms", "recovery_observation_max_ms",
	"overcompensation_count", "overcompensation_index_max",
	"direction_cosine_mean", "direction_cosine_median",
	"conflict_ratio", "startup_difference_ms", "startup_status", "trial_leader",
	"collision_count", "death_count", "mean_route_error", "max_progress",
	"trial_duration_ms", "mean_render_fps", "mean_physics_delta_ms",
	"effective_sample_hz",
	"late_frame_pct", "estimated_frame_drop_pct", "disconnected_frame_pct",
	"controller_disconnect_count", "quality_flag",
	"direction_valid_ms", "simultaneous_active_ms", "xcorr_status",
	"A_start_ms", "B_start_ms", "intensity_difference_mean", "intensity_difference_p95",
	"intensity_difference_max", "xcorr_lag_ms", "xcorr_peak", "xcorr_leader",
	"xcorr_confidence", "route_correction_exposure_ms",
	"route_correction_integral_A", "route_correction_integral_B",
	"p95_route_error",
	"max_route_error", "outside_boundary_ms", "route_length",
]

const PERTURBATION_COLUMNS: PackedStringArray = [
	"analysis_version", "session_id", "trial_id", "perturbation_id",
	"level_id", "onset_ms", "offset_ms", "perturbed_participant", "perturbed_slot",
	"gain", "compensation_status", "compensation_onset_ms",
	"compensation_reaction_ms", "compensation_peak_projection",
	"recovery_status", "recovery_time_ms", "recovery_stable_time_ms",
	"recovery_observation_ms",
	"recovery_censored", "overshoot_status", "overshoot_first_reverse_max",
	"overcompensation_index", "overshoot_round_trips",
]

const GATE_COLUMNS: PackedStringArray = [
	"analysis_version", "session_id", "trial_id", "level_id", "gate_id",
	"attempt_count", "fail_count", "opened",
	"first_forward_speed", "first_direction_cosine", "result_reason",
]

const SEGMENT_COLUMNS: PackedStringArray = [
	"analysis_version", "session_id", "trial_id", "level_id",
	"segment_id", "segment_type", "enter_ms", "exit_ms",
	"entry_speed", "mean_speed", "outside_hits",
]

const CHOICE_COLUMNS: PackedStringArray = [
	"analysis_version", "session_id", "trial_id", "level_id", "fork_id",
	"pref_a", "pref_b", "conflict", "committed_branch", "reversal_count",
]

const REVIEW_QUEUE_COLUMNS: PackedStringArray = [
	"analysis_version", "session_id", "perturbation_id", "trial_id", "level_id",
	"onset_ms", "automatic_valid", "automatic_onset_ms", "automatic_recovery_ms",
	"svg_path", "manual_valid", "manual_onset_ms", "manual_recovery_ms", "note",
]

## 稳定入口：从原始日志重算 results/ 中有数据的结果表。返回 false 表示输入或写出失败。
static func export_session(paths: Dictionary, protocol: ExperimentProtocol = null) -> bool:
	var active_protocol: ExperimentProtocol = protocol if protocol != null else ExperimentProtocol.new()
	var analyzed: Dictionary = analyze_session(paths, active_protocol)
	if analyzed.is_empty():
		return false
	var results_dir: String = str(paths.get("results_directory", ""))
	if results_dir.is_empty():
		results_dir = str(paths.get("directory", "")).path_join("results")
	if results_dir.is_empty():
		return false
	if DirAccess.make_dir_recursive_absolute(results_dir) != OK and not DirAccess.dir_exists_absolute(results_dir):
		return false
	var outputs: Dictionary = {}
	var ok: bool = true
	ok = _write_result_csv(results_dir, "trial_results.csv", TRIAL_COLUMNS, analyzed["trial_results"], outputs) and ok
	ok = _write_result_csv(
		results_dir, "perturbation_results.csv", PERTURBATION_COLUMNS,
		analyzed["perturbation_results"], outputs
	) and ok
	ok = _write_result_csv(results_dir, "gate_results.csv", GATE_COLUMNS, analyzed["gate_results"], outputs) and ok
	ok = _write_result_csv(
		results_dir, "segment_results.csv", SEGMENT_COLUMNS, analyzed["segment_results"], outputs
	) and ok
	ok = _write_result_csv(
		results_dir, "choice_results.csv", CHOICE_COLUMNS, analyzed["choice_results"], outputs
	) and ok
	ok = _write_manifest(
		results_dir.path_join("analysis_manifest.json"),
		analyzed["session"],
		active_protocol,
		outputs
	) and ok
	return ok

## 按需生成 qc/review_queue.csv 与复核 SVG；不写重复窗口表。
static func export_review_package(paths: Dictionary, protocol: ExperimentProtocol = null) -> bool:
	var active_protocol: ExperimentProtocol = protocol if protocol != null else ExperimentProtocol.new()
	var analyzed: Dictionary = analyze_session(paths, active_protocol)
	if analyzed.is_empty():
		return false
	var qc_dir: String = str(paths.get("qc_directory", ""))
	if qc_dir.is_empty():
		qc_dir = str(paths.get("directory", "")).path_join("qc")
	if qc_dir.is_empty():
		return false
	if DirAccess.make_dir_recursive_absolute(qc_dir) != OK and not DirAccess.dir_exists_absolute(qc_dir):
		return false
	return _export_review(
		qc_dir,
		str((analyzed["session"] as Dictionary).get("session_id", "")),
		analyzed["perturbation_results"],
		analyzed["frames_by_trial"],
		active_protocol,
		float(analyzed["force_scale"]),
	)

## 从 raw CSV 计算全部结果行，供导出与汇总复用。失败返回空字典。
static func analyze_session(paths: Dictionary, protocol: ExperimentProtocol = null) -> Dictionary:
	var active_protocol: ExperimentProtocol = protocol if protocol != null else ExperimentProtocol.new()
	var session_rows: Array[Dictionary] = read_csv(str(paths.get("session", "")))
	var frames: Array[Dictionary] = read_csv(str(paths.get("frames", "")))
	var events: Array[Dictionary] = read_csv(str(paths.get("events", "")))
	if session_rows.is_empty() or (frames.is_empty() and events.is_empty()):
		return {}
	var session: Dictionary = session_rows[0]
	var force_scale: float = maxf(_number(session.get("force_max", 1.0)), 0.000001)
	var nominal_sample_hz: float = maxf(
		_number(session.get("physics_ticks_per_second", 60.0)), 1.0
	)
	var session_id: String = str(session.get("session_id", ""))
	var trial_ids: PackedStringArray = PackedStringArray()
	for frame: Dictionary in frames:
		var trial_id: String = str(frame.get("trial_id", ""))
		if not trial_id.is_empty() and not trial_ids.has(trial_id):
			trial_ids.append(trial_id)
	for event: Dictionary in events:
		var trial_id: String = str(event.get("trial_id", ""))
		if not trial_id.is_empty() and not trial_ids.has(trial_id):
			trial_ids.append(trial_id)

	var trial_results: Array[Dictionary] = []
	var perturbation_results: Array[Dictionary] = []
	var frames_by_trial: Dictionary = {}
	for trial_id: String in trial_ids:
		var trial_frames: Array[Dictionary] = _filter_trial(frames, trial_id)
		var trial_events: Array[Dictionary] = _filter_trial(events, trial_id)
		frames_by_trial[trial_id] = trial_frames
		var trial_result: Dictionary = analyze_trial(
			trial_frames, trial_events, active_protocol, force_scale, nominal_sample_hz
		)
		trial_result["session_id"] = session_id
		for identity_field: String in [
			"station_id", "dyad_id", "participant_A", "participant_B",
			"relation_condition", "side_assignment",
		]:
			trial_result[identity_field] = session.get(identity_field, "")
		var trial_perturbations: Array[Dictionary] = []
		var on_count: int = 0
		for event_index: int in trial_events.size():
			var event: Dictionary = trial_events[event_index]
			if str(event.get("event_type", "")) != "perturb_on":
				continue
			on_count += 1
			var slot: String = str(event.get("slot", ""))
			var trial_end_ms: float = _last_time_ms(trial_frames, trial_events)
			var offset_ms: float = trial_end_ms
			var observation_end_ms: float = trial_end_ms
			for later_index: int in range(event_index + 1, trial_events.size()):
				var later: Dictionary = trial_events[later_index]
				var later_type: String = str(later.get("event_type", ""))
				if later_type == "perturb_on":
					observation_end_ms = minf(
						observation_end_ms,
						_number(later.get("trial_elapsed_ms", observation_end_ms)),
					)
					break
				if (
					later_type == "perturb_off"
					and str(later.get("slot", "")) == slot
				):
					offset_ms = _number(later.get("trial_elapsed_ms", offset_ms))
			offset_ms = minf(offset_ms, observation_end_ms)
			var perturbation_id: String = "%s-P%03d" % [trial_id, on_count]
			var perturbation: Dictionary = analyze_perturbation(
				trial_frames, event, offset_ms, active_protocol, force_scale, observation_end_ms
			)
			perturbation["analysis_version"] = ExperimentProtocol.ANALYSIS_VERSION
			perturbation["session_id"] = session_id
			perturbation["trial_id"] = trial_id
			perturbation["perturbation_id"] = perturbation_id
			perturbation["level_id"] = str(event.get("level_id", ""))
			perturbation_results.append(perturbation)
			trial_perturbations.append(perturbation)
		_add_perturbation_summary(trial_result, trial_perturbations)
		trial_results.append(trial_result)

	var gate_results: Array[Dictionary] = []
	var segment_results: Array[Dictionary] = []
	var choice_results: Array[Dictionary] = []
	for trial_id: String in trial_ids:
		var trial_frames: Array[Dictionary] = _filter_trial(frames, trial_id)
		var trial_events: Array[Dictionary] = _filter_trial(events, trial_id)
		gate_results.append_array(_analyze_gates(trial_frames, trial_events, session_id))
		segment_results.append_array(_analyze_segments(trial_frames, trial_events, session_id))
		choice_results.append_array(_analyze_choices(trial_events, session_id))
	return {
		"session": session,
		"frames": frames,
		"events": events,
		"trial_results": trial_results,
		"perturbation_results": perturbation_results,
		"gate_results": gate_results,
		"segment_results": segment_results,
		"choice_results": choice_results,
		"frames_by_trial": frames_by_trial,
		"force_scale": force_scale,
	}

static func read_csv(path: String) -> Array[Dictionary]:
	return _read_csv(path)

## 按门聚合 attempt / fail / open 事件。
static func _analyze_gates(
	frames: Array[Dictionary],
	events: Array[Dictionary],
	session_id: String,
) -> Array[Dictionary]:
	var by_gate: Dictionary = {}
	var level_id: String = _first_value(frames, events, "level_id")
	var trial_id: String = _first_value(frames, events, "trial_id")
	for event: Dictionary in events:
		var et: String = str(event.get("event_type", ""))
		if et != "gate_attempt" and et != "gate_failed" and et != "gate_opened":
			continue
		var gate_id: String = str(event.get("component_id", event.get("note", "gate")))
		if not by_gate.has(gate_id):
			by_gate[gate_id] = {
				"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
				"session_id": session_id,
				"trial_id": trial_id,
				"level_id": level_id,
				"gate_id": gate_id,
				"attempt_count": 0,
				"fail_count": 0,
				"opened": 0,
				"first_forward_speed": "",
				"first_direction_cosine": "",
				"result_reason": "",
			}
		var row: Dictionary = by_gate[gate_id] as Dictionary
		if et == "gate_attempt":
			row["attempt_count"] = int(row["attempt_count"]) + 1
			if str(row["first_forward_speed"]) == "":
				row["result_reason"] = str(event.get("result_reason", ""))
		elif et == "gate_failed":
			row["fail_count"] = int(row["fail_count"]) + 1
			row["result_reason"] = str(event.get("result_reason", row["result_reason"]))
		elif et == "gate_opened":
			row["opened"] = 1
			row["result_reason"] = "opened"
	var out: Array[Dictionary] = []
	for key: Variant in by_gate.keys():
		out.append(by_gate[key] as Dictionary)
	return out

## 按弯道/减速等实验路段聚合进入离开与速度。
static func _analyze_segments(
	frames: Array[Dictionary],
	events: Array[Dictionary],
	session_id: String,
) -> Array[Dictionary]:
	var level_id: String = _first_value(frames, events, "level_id")
	var trial_id: String = _first_value(frames, events, "trial_id")
	var out: Array[Dictionary] = []
	var open: Dictionary = {}
	for event: Dictionary in events:
		var et: String = str(event.get("event_type", ""))
		var seg_id: String = str(event.get("segment_id", event.get("component_id", "")))
		var seg_type: String = str(event.get("note", ""))
		if et == "segment_enter":
			open[seg_id] = {
				"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
				"session_id": session_id,
				"trial_id": trial_id,
				"level_id": level_id,
				"segment_id": seg_id,
				"segment_type": seg_type,
				"enter_ms": _number(event.get("trial_elapsed_ms", 0.0)),
				"exit_ms": "",
				"entry_speed": "",
				"mean_speed": "",
				"outside_hits": 0,
			}
		elif et == "segment_leave" and open.has(seg_id):
			var row: Dictionary = open[seg_id] as Dictionary
			row["exit_ms"] = _number(event.get("trial_elapsed_ms", 0.0))
			var speeds: Array[float] = []
			var enter_ms: float = _number(row["enter_ms"])
			var exit_ms: float = _number(row["exit_ms"])
			for frame: Dictionary in frames:
				var t: float = _number(frame.get("trial_elapsed_ms", -1.0))
				if t < enter_ms or t > exit_ms:
					continue
				speeds.append(_number(frame.get("speed", 0.0)))
			if not speeds.is_empty():
				row["entry_speed"] = speeds[0]
				var sum: float = 0.0
				for s: float in speeds:
					sum += s
				row["mean_speed"] = sum / float(speeds.size())
			out.append(row)
			open.erase(seg_id)
	return out

## 按岔路聚合偏好、冲突与最终提交。
static func _analyze_choices(
	events: Array[Dictionary],
	session_id: String,
) -> Array[Dictionary]:
	var by_fork: Dictionary = {}
	var level_id: String = ""
	var trial_id: String = ""
	for event: Dictionary in events:
		level_id = str(event.get("level_id", level_id))
		trial_id = str(event.get("trial_id", trial_id))
		var et: String = str(event.get("event_type", ""))
		if not et.begins_with("choice_") and not et.begins_with("branch_"):
			continue
		var fork_id: String = str(event.get("component_id", ""))
		if fork_id.is_empty():
			continue
		if not by_fork.has(fork_id):
			by_fork[fork_id] = {
				"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
				"session_id": session_id,
				"trial_id": trial_id,
				"level_id": level_id,
				"fork_id": fork_id,
				"pref_a": "",
				"pref_b": "",
				"conflict": 0,
				"committed_branch": "",
				"reversal_count": 0,
			}
		var row: Dictionary = by_fork[fork_id] as Dictionary
		match et:
			"choice_preference_A":
				row["pref_a"] = str(event.get("branch", ""))
			"choice_preference_B":
				row["pref_b"] = str(event.get("branch", ""))
			"choice_conflict":
				row["conflict"] = 1
			"branch_committed":
				row["committed_branch"] = str(event.get("branch", ""))
			"branch_reversal":
				row["reversal_count"] = int(row["reversal_count"]) + 1
				row["committed_branch"] = str(event.get("branch", row["committed_branch"]))
	var out: Array[Dictionary] = []
	for key: Variant in by_fork.keys():
		out.append(by_fork[key] as Dictionary)
	return out

## 纯函数：输入一个 trial 的字典行，返回一行 trial_results。
static func analyze_trial(
	frames: Array[Dictionary],
	events: Array[Dictionary],
	protocol: ExperimentProtocol,
	force_scale: float = 1.0,
	nominal_sample_hz: float = 60.0,
) -> Dictionary:
	var result: Dictionary = {
		"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
		"session_id": _first_value(frames, events, "session_id"),
		"trial_id": _first_value(frames, events, "trial_id"),
		"level_id": _first_value(frames, events, "level_id"),
		"level_attempt_index": _first_value(frames, events, "level_attempt_index"),
		"protocol_version": _first_value(frames, events, "protocol_version"),
	}
	var cosines: Array[float] = []
	var differences: Array[float] = []
	var errors: Array[float] = []
	var render_fps_values: Array[float] = []
	var simultaneous_ms: float = 0.0
	var conflict_ms: float = 0.0
	var direction_ms: float = 0.0
	var outside_ms: float = 0.0
	var correction_exposure_ms: float = 0.0
	var route_length: float = 0.0
	var max_progress: float = 0.0
	var correction_a: float = 0.0
	var correction_b: float = 0.0
	var total_sample_ms: float = 0.0
	var expected_frame_slots: int = 0
	var estimated_dropped_slots: int = 0
	var late_frame_count: int = 0
	var disconnected_frame_count: int = 0
	var previous_position: Vector2
	var has_previous_position: bool = false
	var scale: float = maxf(force_scale, 0.000001)
	for frame: Dictionary in frames:
		var dt_ms: float = _frame_delta_ms(frame)
		total_sample_ms += dt_ms
		var expected_slots: int = maxi(
			1, int(round(dt_ms * maxf(nominal_sample_hz, 1.0) / 1000.0))
		)
		expected_frame_slots += expected_slots
		estimated_dropped_slots += expected_slots - 1
		if dt_ms > (1000.0 / maxf(nominal_sample_hz, 1.0)) * 1.5:
			late_frame_count += 1
		var render_fps: float = _number(frame.get("render_fps", 0.0))
		if render_fps > 0.0:
			render_fps_values.append(render_fps)
		var a_connected: String = str(frame.get("A_connected", ""))
		var b_connected: String = str(frame.get("B_connected", ""))
		if (
			str(frame.get("system_quality", "")) == "disconnected"
			or (not a_connected.is_empty() and not _truthy(a_connected))
			or (not b_connected.is_empty() and not _truthy(b_connected))
		):
			disconnected_frame_count += 1
		var a: Vector2 = _force(frame, "A")
		var b: Vector2 = _force(frame, "B")
		var a_norm: float = a.length() / scale
		var b_norm: float = b.length() / scale
		if a_norm > protocol.activity_threshold and b_norm > protocol.activity_threshold:
			var cosine: float = a.dot(b) / maxf(a.length() * b.length(), 0.000001)
			cosines.append(cosine)
			differences.append(absf(a_norm - b_norm))
			simultaneous_ms += dt_ms
			direction_ms += dt_ms
			if cosine < protocol.conflict_cosine_threshold:
				conflict_ms += dt_ms
		var distance: float = _number(frame.get("route_error_distance", 0.0))
		errors.append(distance)
		max_progress = maxf(max_progress, _number(frame.get("route_max_progress", 0.0)))
		if not _truthy(frame.get("inside_boundary", true)):
			outside_ms += dt_ms
		var position := Vector2(
			_number(frame.get("core_x", 0.0)), _number(frame.get("core_y", 0.0))
		)
		if has_previous_position:
			route_length += position.distance_to(previous_position)
		previous_position = position
		has_previous_position = true
		var error := Vector2(
			_number(frame.get("route_error_x", 0.0)),
			_number(frame.get("route_error_y", 0.0))
		)
		if error.length() >= protocol.compensation_min_error:
			correction_exposure_ms += dt_ms
			var correction_direction: Vector2 = -error.normalized()
			correction_a += maxf(a.dot(correction_direction) / scale, 0.0) * dt_ms
			correction_b += maxf(b.dot(correction_direction) / scale, 0.0) * dt_ms

	var a_start: Variant = _sustained_start(frames, "A", protocol, scale)
	var b_start: Variant = _sustained_start(frames, "B", protocol, scale)
	result["A_start_ms"] = a_start
	result["B_start_ms"] = b_start
	if a_start == null or b_start == null:
		result["startup_difference_ms"] = null
		result["startup_status"] = (
			"missing_both" if a_start == null and b_start == null
			else ("missing_A" if a_start == null else "missing_B")
		)
	else:
		result["startup_difference_ms"] = float(b_start) - float(a_start)
		result["startup_status"] = "ok"

	var xcorr: Dictionary = _cross_correlation(frames, protocol, scale)
	for key: Variant in xcorr:
		result[key] = xcorr[key]
	result["direction_cosine_mean"] = _mean(cosines)
	result["direction_cosine_median"] = _percentile(cosines, 0.5)
	result["direction_valid_ms"] = direction_ms
	result["intensity_difference_mean"] = _mean(differences)
	result["intensity_difference_p95"] = _percentile(differences, 0.95)
	result["intensity_difference_max"] = _maximum(differences)
	result["conflict_ratio"] = conflict_ms / simultaneous_ms if simultaneous_ms > 0.0 else null
	result["simultaneous_active_ms"] = simultaneous_ms
	result["route_correction_exposure_ms"] = (
		correction_exposure_ms if correction_exposure_ms > 0.0 else null
	)
	result["route_correction_integral_A"] = (
		correction_a if correction_exposure_ms > 0.0 else null
	)
	result["route_correction_integral_B"] = (
		correction_b if correction_exposure_ms > 0.0 else null
	)
	result["trial_leader"] = _trial_leader(a_start, b_start, xcorr, correction_a, correction_b)
	result["collision_count"] = _count_event(events, "collision")
	result["death_count"] = _count_event(events, "death_collision")
	result["outcome"] = _trial_outcome(events)
	result["quit_reason"] = _quit_reason(frames, events, str(result["outcome"]))
	result["trial_duration_ms"] = _last_time_ms(frames, events)
	result["mean_render_fps"] = _mean(render_fps_values)
	result["mean_physics_delta_ms"] = (
		total_sample_ms / float(frames.size()) if not frames.is_empty() else null
	)
	result["effective_sample_hz"] = (
		float(frames.size()) * 1000.0 / total_sample_ms if total_sample_ms > 0.0 else null
	)
	result["late_frame_pct"] = (
		100.0 * float(late_frame_count) / float(frames.size())
		if not frames.is_empty() else null
	)
	result["estimated_frame_drop_pct"] = (
		100.0 * float(estimated_dropped_slots) / float(expected_frame_slots)
		if expected_frame_slots > 0 else null
	)
	result["disconnected_frame_pct"] = (
		100.0 * float(disconnected_frame_count) / float(frames.size())
		if not frames.is_empty() else null
	)
	result["controller_disconnect_count"] = _count_event(events, "controller_disconnect")
	result["quality_flag"] = _quality_flag(result, protocol)
	var run_start_ms: Variant = _event_time(events, "run_start")
	result["completion_time_ms"] = (
		_last_time_ms(frames, events) - float(run_start_ms) if run_start_ms != null else null
	)
	result["mean_route_error"] = _mean(errors)
	result["p95_route_error"] = _percentile(errors, 0.95)
	result["max_route_error"] = _maximum(errors)
	result["max_progress"] = max_progress
	result["outside_boundary_ms"] = outside_ms
	result["route_length"] = route_length
	if str(result["outcome"]) in ["quit", "aborted", "incomplete", "restarted"]:
		_clear_invalid_trial_metrics(result)
	return result

static func _add_perturbation_summary(
	result: Dictionary, perturbations: Array[Dictionary]
) -> void:
	var participants: Dictionary = {}
	var gains: Array[float] = []
	var onsets: Array[float] = []
	var offsets: Array[float] = []
	var compensation_reactions: Array[float] = []
	var recovery_times: Array[float] = []
	var recovery_observations: Array[float] = []
	var compensation_valid_count: int = 0
	var recovery_recovered_count: int = 0
	var recovery_censored_count: int = 0
	var overcompensation_count: int = 0
	var overcompensation_indices: Array[float] = []
	for perturbation: Dictionary in perturbations:
		var participant: String = str(perturbation.get("perturbed_participant", ""))
		if participant in ["A", "B"]:
			participants[participant] = true
		_append_number(gains, perturbation.get("gain"))
		_append_number(onsets, perturbation.get("onset_ms"))
		_append_number(offsets, perturbation.get("offset_ms"))
		if str(perturbation.get("compensation_status", "")) == "valid":
			compensation_valid_count += 1
			_append_number(
				compensation_reactions,
				perturbation.get("compensation_reaction_ms"),
			)
		var recovery_status: String = str(perturbation.get("recovery_status", ""))
		if recovery_status == "recovered":
			recovery_recovered_count += 1
			_append_number(recovery_times, perturbation.get("recovery_time_ms"))
		elif recovery_status == "censored":
			recovery_censored_count += 1
		_append_number(
			recovery_observations,
			perturbation.get("recovery_observation_ms"),
		)
		if str(perturbation.get("overshoot_status", "")) == "overshoot":
			overcompensation_count += 1
			_append_number(
				overcompensation_indices,
				perturbation.get("overcompensation_index"),
			)
	var participant_labels: PackedStringArray = PackedStringArray()
	for participant: String in ["A", "B"]:
		if participants.has(participant):
			participant_labels.append(participant)
	result["perturbation_count"] = perturbations.size()
	result["perturbed_participants"] = (
		"none" if participant_labels.is_empty() else ";".join(participant_labels)
	)
	result["perturb_gain_mean"] = _mean(gains)
	result["perturb_first_onset_ms"] = _percentile(onsets, 0.0)
	result["perturb_last_offset_ms"] = _maximum(offsets)
	result["compensation_valid_count"] = compensation_valid_count
	result["compensation_reaction_median_ms"] = _percentile(
		compensation_reactions, 0.5
	)
	result["recovery_recovered_count"] = recovery_recovered_count
	result["recovery_censored_count"] = recovery_censored_count
	result["recovery_time_median_ms"] = _percentile(recovery_times, 0.5)
	result["recovery_observation_max_ms"] = _maximum(recovery_observations)
	result["overcompensation_count"] = overcompensation_count
	result["overcompensation_index_max"] = _maximum(overcompensation_indices)

static func _append_number(values: Array[float], value: Variant) -> void:
	if value == null or str(value).is_empty():
		return
	values.append(_number(value))

static func _quality_flag(result: Dictionary, protocol: ExperimentProtocol) -> String:
	var flags: PackedStringArray = PackedStringArray()
	var effective: Variant = result.get("effective_sample_hz")
	var dropped: Variant = result.get("estimated_frame_drop_pct")
	var disconnected: Variant = result.get("disconnected_frame_pct")
	if effective == null:
		flags.append("no_frame_data")
	elif float(effective) < protocol.minimum_effective_sample_hz:
		flags.append("low_sample_rate")
	if dropped != null and float(dropped) > protocol.maximum_frame_drop_pct:
		flags.append("high_frame_drop")
	if (
		(disconnected != null and float(disconnected) > 0.0)
		or int(result.get("controller_disconnect_count", 0)) > 0
	):
		flags.append("controller_disconnected")
	return "ok" if flags.is_empty() else ";".join(flags)

static func _quit_reason(
	frames: Array[Dictionary], events: Array[Dictionary], outcome: String
) -> String:
	if outcome != "quit":
		return ""
	if not frames.is_empty():
		var last_frame: Dictionary = frames[-1]
		if (
			str(last_frame.get("system_quality", "")) == "disconnected"
			or (
				not str(last_frame.get("A_connected", "")).is_empty()
				and not _truthy(last_frame.get("A_connected"))
			)
			or (
				not str(last_frame.get("B_connected", "")).is_empty()
				and not _truthy(last_frame.get("B_connected"))
			)
		):
			return "controller_disconnected"
	var candidate: String = ""
	for i: int in range(events.size() - 1, -1, -1):
		var event_type: String = str(events[i].get("event_type", ""))
		if event_type == "trial_end" or event_type == "quit_mid_trial":
			var note: String = str(events[i].get("note", ""))
			if not note.is_empty():
				candidate = note
				break
	return candidate if QUIT_REASONS.has(candidate) else "unspecified"

static func _clear_invalid_trial_metrics(result: Dictionary) -> void:
	for field: String in [
		"completion_time_ms", "direction_cosine_mean", "direction_cosine_median",
		"conflict_ratio", "startup_difference_ms", "startup_status", "trial_leader",
		"mean_route_error", "max_progress", "direction_valid_ms",
		"simultaneous_active_ms", "xcorr_status", "A_start_ms", "B_start_ms",
		"intensity_difference_mean", "intensity_difference_p95",
		"intensity_difference_max", "xcorr_lag_ms", "xcorr_peak",
		"xcorr_leader", "xcorr_confidence", "route_correction_exposure_ms",
		"route_correction_integral_A", "route_correction_integral_B",
		"p95_route_error", "max_route_error", "outside_boundary_ms",
		"route_length",
	]:
		result[field] = null

## 纯函数：分析单次 perturb_on。offset_ms 为匹配 perturb_off 或观察终点。
static func analyze_perturbation(
	frames: Array[Dictionary],
	on_event: Dictionary,
	offset_ms: float,
	protocol: ExperimentProtocol,
	force_scale: float = 1.0,
	observation_end_ms: float = INF,
) -> Dictionary:
	var onset_ms: float = _number(on_event.get("trial_elapsed_ms", 0.0))
	var frame_end_ms: float = _last_time_ms(frames, [])
	var analysis_end_ms: float = (
		frame_end_ms if observation_end_ms == INF else observation_end_ms
	)
	analysis_end_ms = maxf(analysis_end_ms, onset_ms)
	offset_ms = clampf(offset_ms, onset_ms, analysis_end_ms)
	var slot: int = int(_number(on_event.get("slot", -1)))
	var onset_frame: Dictionary = _nearest_frame(frames, onset_ms)
	var perturbed: String = "A" if int(_number(onset_frame.get("A_slot", 0))) == slot else "B"
	var responder: String = "B" if perturbed == "A" else "A"
	var baseline: Array[Dictionary] = _window(
		frames, onset_ms - protocol.perturbation_baseline_ms, onset_ms
	)
	var result: Dictionary = {
		"onset_ms": onset_ms,
		"offset_ms": offset_ms,
		"perturbed_participant": perturbed,
		"perturbed_slot": slot,
		"gain": on_event.get("gain", ""),
	}
	if baseline.is_empty():
		_set_ineligible_perturbation(result, "not_eligible")
		return result
	var baseline_force := Vector2(
		_median_field(baseline, "%s_force_x" % responder),
		_median_field(baseline, "%s_force_y" % responder)
	)
	var baseline_error_vector := Vector2(
		_median_field(baseline, "route_error_x"),
		_median_field(baseline, "route_error_y")
	)
	var baseline_error: float = _median_field(baseline, "route_error_distance")
	if baseline_error_vector.length() < protocol.compensation_min_error:
		_set_ineligible_perturbation(result, "not_eligible")
		return result
	var direction: Vector2 = -baseline_error_vector.normalized()
	var scale: float = maxf(force_scale, 0.000001)
	var peak_projection: float = -INF
	var candidate_start: float = -1.0
	var compensation_onset: Variant = null
	for frame: Dictionary in frames:
		var time_ms: float = _number(frame.get("trial_elapsed_ms", 0.0))
		if time_ms < onset_ms:
			continue
		if time_ms > offset_ms:
			break
		var delta_force: Vector2 = _force(frame, responder) - baseline_force
		var projection: float = delta_force.dot(direction) / scale
		peak_projection = maxf(peak_projection, projection)
		if projection >= protocol.compensation_projection_threshold:
			if candidate_start < 0.0:
				candidate_start = time_ms
			if time_ms - candidate_start >= protocol.compensation_sustain_ms:
				var check_time: float = candidate_start + protocol.compensation_error_check_ms
				if check_time > offset_ms:
					continue
				var check_frame: Dictionary = _nearest_frame(frames, check_time)
				if (
					not check_frame.is_empty()
					and _number(check_frame.get("trial_elapsed_ms", 0.0)) >= check_time - 50.0
					and _number(check_frame.get("trial_elapsed_ms", INF)) <= offset_ms
					and _number(check_frame.get("route_error_distance", INF))
					<= baseline_error * (1.0 - protocol.compensation_error_drop_ratio)
				):
					compensation_onset = candidate_start
					break
		else:
			candidate_start = -1.0
	result["compensation_peak_projection"] = peak_projection if peak_projection > -INF else null
	if compensation_onset == null:
		var observed_until: float = offset_ms
		result["compensation_status"] = (
			"censored" if observed_until < onset_ms + protocol.compensation_error_check_ms
			else "no_valid_compensation"
		)
		result["compensation_onset_ms"] = null
		result["compensation_reaction_ms"] = null
	else:
		result["compensation_status"] = "valid"
		result["compensation_onset_ms"] = compensation_onset
		result["compensation_reaction_ms"] = float(compensation_onset) - onset_ms

	var recovery: Dictionary = _recovery(
		frames, baseline, onset_ms, offset_ms, analysis_end_ms, protocol
	)
	for key: Variant in recovery:
		result[key] = recovery[key]
	var overshoot: Dictionary = _overshoot(
		frames, baseline, onset_ms, analysis_end_ms, protocol
	)
	for key: Variant in overshoot:
		result[key] = overshoot[key]
	return result

static func _cross_correlation(
	frames: Array[Dictionary], protocol: ExperimentProtocol, force_scale: float
) -> Dictionary:
	var inactive: Dictionary = {
		"xcorr_lag_ms": null, "xcorr_peak": null, "xcorr_leader": "ambiguous",
		"xcorr_confidence": 0.0, "xcorr_status": "low_activity",
	}
	if frames.size() < 4:
		return inactive
	var active_ms: float = 0.0
	for frame: Dictionary in frames:
		if (
			_force(frame, "A").length() / force_scale > protocol.activity_threshold
			or _force(frame, "B").length() / force_scale > protocol.activity_threshold
		):
			active_ms += _frame_delta_ms(frame)
	if active_ms < protocol.cross_correlation_min_active_ms:
		return inactive
	var dt_ms: float = maxf(_median_delta_ms(frames), 1.0)
	var smooth_radius: int = maxi(0, int(round(protocol.force_smoothing_ms / dt_ms / 2.0)))
	var a_smooth: Array[Vector2] = _smooth_force(frames, "A", smooth_radius)
	var b_smooth: Array[Vector2] = _smooth_force(frames, "B", smooth_radius)
	var da: Array[Vector2] = []
	var db: Array[Vector2] = []
	for i: int in range(1, frames.size()):
		da.append(a_smooth[i] - a_smooth[i - 1])
		db.append(b_smooth[i] - b_smooth[i - 1])
	var max_lag: int = mini(int(round(protocol.cross_correlation_max_lag_ms / dt_ms)), da.size() - 2)
	if max_lag < 1:
		return inactive
	var best_lag: int = 0
	var best_correlation: float = 0.0
	var best_abs: float = -1.0
	var second_abs: float = 0.0
	for lag: int in range(-max_lag, max_lag + 1):
		var correlation: Variant = _lag_correlation(da, db, lag)
		if correlation == null:
			continue
		var magnitude: float = absf(float(correlation))
		if magnitude > best_abs:
			second_abs = best_abs
			best_abs = magnitude
			best_correlation = float(correlation)
			best_lag = lag
		elif magnitude > second_abs:
			second_abs = magnitude
	if best_abs < 0.0:
		return inactive
	var lag_ms: float = float(best_lag) * dt_ms
	var leader: String = "ambiguous"
	if absf(lag_ms) >= dt_ms * 0.5:
		leader = "A" if lag_ms > 0.0 else "B"
	return {
		"xcorr_lag_ms": lag_ms,
		"xcorr_peak": best_correlation,
		"xcorr_leader": leader,
		"xcorr_confidence": clampf(best_abs * (0.5 + 0.5 * maxf(best_abs - second_abs, 0.0)), 0.0, 1.0),
		"xcorr_status": "ok",
	}

static func _lag_correlation(a: Array[Vector2], b: Array[Vector2], lag: int) -> Variant:
	var sum_dot: float = 0.0
	var sum_a: float = 0.0
	var sum_b: float = 0.0
	var count: int = 0
	for i: int in a.size():
		var j: int = i + lag
		if j < 0 or j >= b.size():
			continue
		sum_dot += a[i].dot(b[j])
		sum_a += a[i].length_squared()
		sum_b += b[j].length_squared()
		count += 1
	if count < 3 or sum_a <= 0.000001 or sum_b <= 0.000001:
		return null
	return sum_dot / sqrt(sum_a * sum_b)

static func _recovery(
	frames: Array[Dictionary],
	baseline: Array[Dictionary],
	onset_ms: float,
	search_start_ms: float,
	observation_end_ms: float,
	protocol: ExperimentProtocol,
) -> Dictionary:
	# 路线误差是跨弯道仍有稳定含义的任务状态。速度和角速度会随路径自然变化，
	# 用扰动前 200ms 的窄带同时约束三者会把正常前进误判为永不恢复。
	# “不差于基线 + 稳健容差”为单侧标准，因此补偿后误差进一步下降也算恢复。
	var values: Array[float] = _field_values(baseline, "route_error_distance")
	var median: Variant = _percentile(values, 0.5)
	var center: float = float(median) if median != null else 0.0
	var deviations: Array[float] = []
	for value: float in values:
		deviations.append(absf(value - center))
	var mad: Variant = _percentile(deviations, 0.5)
	var tolerance: float = maxf(
		protocol.recovery_error_floor,
		protocol.recovery_mad_multiplier * (float(mad) if mad != null else 0.0),
	)
	var candidate: float = -1.0
	var last_time: float = onset_ms
	for frame: Dictionary in frames:
		var time_ms: float = _number(frame.get("trial_elapsed_ms", 0.0))
		if time_ms < search_start_ms:
			continue
		if time_ms > observation_end_ms:
			break
		last_time = time_ms
		var stable: bool = (
			_number(frame.get("route_error_distance", INF)) <= center + tolerance
		)
		if stable:
			if candidate < 0.0:
				candidate = time_ms
			if time_ms - candidate >= protocol.recovery_sustain_ms:
				return {
					"recovery_status": "recovered",
					"recovery_time_ms": candidate - onset_ms,
					"recovery_stable_time_ms": candidate - onset_ms,
					"recovery_observation_ms": time_ms - onset_ms,
					"recovery_censored": 0,
				}
		else:
			candidate = -1.0
	return {
		"recovery_status": "censored",
		"recovery_time_ms": null,
		"recovery_stable_time_ms": maxf(last_time - onset_ms, 0.0),
		"recovery_observation_ms": maxf(last_time - onset_ms, 0.0),
		"recovery_censored": 1,
	}

static func _overshoot(
	frames: Array[Dictionary],
	baseline: Array[Dictionary],
	onset_ms: float,
	observation_end_ms: float,
	protocol: ExperimentProtocol,
) -> Dictionary:
	var initial: float = _median_field(baseline, "route_signed_error")
	if absf(initial) < protocol.overshoot_hysteresis:
		return {
			"overshoot_status": "not_eligible", "overshoot_first_reverse_max": null,
			"overcompensation_index": null, "overshoot_round_trips": 0,
		}
	var initial_sign: float = signf(initial)
	var state: int = 1
	var crossings: int = 0
	var first_reverse_max: float = 0.0
	for frame: Dictionary in frames:
		var time_ms: float = _number(frame.get("trial_elapsed_ms", 0.0))
		if time_ms < onset_ms:
			continue
		if time_ms > observation_end_ms:
			break
		var signed_error: float = _number(frame.get("route_signed_error", 0.0))
		var side: int = 0
		if signed_error * initial_sign > protocol.overshoot_hysteresis:
			side = 1
		elif signed_error * initial_sign < -protocol.overshoot_hysteresis:
			side = -1
		if side != 0 and side != state:
			crossings += 1
			state = side
		if state == -1:
			first_reverse_max = maxf(first_reverse_max, absf(signed_error))
	var round_trips: int = crossings / 2
	return {
		"overshoot_status": "overshoot" if crossings > 0 else "none",
		"overshoot_first_reverse_max": first_reverse_max if crossings > 0 else 0.0,
		"overcompensation_index": first_reverse_max / absf(initial) if crossings > 0 else 0.0,
		"overshoot_round_trips": round_trips,
	}

static func _trial_leader(
	a_start: Variant, b_start: Variant, xcorr: Dictionary, correction_a: float, correction_b: float
) -> String:
	var a_votes: int = 0
	var b_votes: int = 0
	if a_start != null and b_start != null:
		if float(a_start) + 50.0 < float(b_start):
			a_votes += 1
		elif float(b_start) + 50.0 < float(a_start):
			b_votes += 1
	var xcorr_leader: String = str(xcorr.get("xcorr_leader", "ambiguous"))
	if xcorr_leader == "A":
		a_votes += 1
	elif xcorr_leader == "B":
		b_votes += 1
	var correction_total: float = correction_a + correction_b
	if correction_total > 0.0:
		if correction_a / correction_total > 0.60:
			a_votes += 1
		elif correction_b / correction_total > 0.60:
			b_votes += 1
	return "A" if a_votes > b_votes else ("B" if b_votes > a_votes else "ambiguous")

static func _export_review(
	directory: String,
	session_id: String,
	perturbations: Array[Dictionary],
	frames_by_trial: Dictionary,
	protocol: ExperimentProtocol,
	force_scale: float,
) -> bool:
	var queue_path: String = directory.path_join("review_queue.csv")
	var manual_by_id: Dictionary = {}
	for old: Dictionary in _read_csv(queue_path):
		manual_by_id[str(old.get("perturbation_id", ""))] = old
	var ranked: Array[Dictionary] = []
	for perturbation: Dictionary in perturbations:
		var copy: Dictionary = perturbation.duplicate()
		copy["_rank"] = ("%s|%s" % [session_id, perturbation["perturbation_id"]]).sha256_text()
		ranked.append(copy)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["_rank"]) < str(b["_rank"]))
	var sample_count: int = int(ceil(float(ranked.size()) * protocol.review_fraction))
	var selected: Array[Dictionary] = ranked.slice(0, sample_count)
	var queue: Array[Dictionary] = []
	var svg_ok: bool = true
	for perturbation: Dictionary in selected:
		var perturbation_id: String = str(perturbation["perturbation_id"])
		var trial_id: String = str(perturbation["trial_id"])
		var trial_frames: Array[Dictionary] = frames_by_trial.get(trial_id, [])
		var svg_filename: String = "review_%s.svg" % _safe_filename(perturbation_id)
		var old: Dictionary = manual_by_id.get(perturbation_id, {})
		var queue_row: Dictionary = {
			"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
			"session_id": session_id,
			"perturbation_id": perturbation_id,
			"trial_id": trial_id,
			"level_id": perturbation.get("level_id", ""),
			"onset_ms": perturbation.get("onset_ms", ""),
			"automatic_valid": 1 if perturbation.get("compensation_status") == "valid" else 0,
			"automatic_onset_ms": perturbation.get("compensation_onset_ms", ""),
			"automatic_recovery_ms": perturbation.get("recovery_time_ms", ""),
			"svg_path": svg_filename,
			"manual_valid": old.get("manual_valid", ""),
			"manual_onset_ms": old.get("manual_onset_ms", ""),
			"manual_recovery_ms": old.get("manual_recovery_ms", ""),
			"note": old.get("note", ""),
		}
		queue.append(queue_row)
		var review_frames: Array[Dictionary] = _window(
			trial_frames,
			_number(perturbation["onset_ms"]) - protocol.review_window_before_ms,
			_number(perturbation["onset_ms"]) + protocol.review_window_after_ms
		)
		var projection_values: Array[float] = _review_projections(
			trial_frames, review_frames, perturbation, protocol, force_scale
		)
		svg_ok = _write_review_svg(
			directory.path_join(svg_filename), perturbation_id, review_frames,
			projection_values, perturbation
		) and svg_ok
	var agreement: Dictionary = review_agreement(queue, session_id, protocol)
	return (
		svg_ok
		and _write_csv(queue_path, REVIEW_QUEUE_COLUMNS, queue)
		and _write_json(directory.path_join("review_report.json"), agreement)
	)

static func _review_projections(
	all_frames: Array[Dictionary],
	review_frames: Array[Dictionary],
	perturbation: Dictionary,
	protocol: ExperimentProtocol,
	force_scale: float,
) -> Array[float]:
	var onset: float = _number(perturbation["onset_ms"])
	var baseline: Array[Dictionary] = _window(
		all_frames, onset - protocol.perturbation_baseline_ms, onset
	)
	var responder: String = "B" if perturbation["perturbed_participant"] == "A" else "A"
	var baseline_force := Vector2(
		_median_field(baseline, "%s_force_x" % responder),
		_median_field(baseline, "%s_force_y" % responder)
	)
	var error := Vector2(
		_median_field(baseline, "route_error_x"),
		_median_field(baseline, "route_error_y")
	)
	var direction: Vector2 = -error.normalized() if error.length() > 0.0 else Vector2.ZERO
	var values: Array[float] = []
	for frame: Dictionary in review_frames:
		values.append(
			(_force(frame, responder) - baseline_force).dot(direction)
			/ maxf(force_scale, 0.000001)
		)
	return values

static func _write_review_svg(
	path: String,
	perturbation_id: String,
	frames: Array[Dictionary],
	projections: Array[float],
	perturbation: Dictionary,
) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var width: float = 1000.0
	var height: float = 620.0
	var left: float = 70.0
	var right: float = 970.0
	var top: float = 55.0
	var bottom: float = 570.0
	var onset: float = _number(perturbation["onset_ms"])
	var times: Array[float] = []
	var error_values: Array[float] = []
	var speed_values: Array[float] = []
	var angular_values: Array[float] = []
	var a_force_values: Array[float] = []
	var b_force_values: Array[float] = []
	for frame: Dictionary in frames:
		times.append(_number(frame.get("trial_elapsed_ms", 0.0)) - onset)
		error_values.append(_number(frame.get("route_signed_error", 0.0)))
		speed_values.append(_number(frame.get("speed", 0.0)))
		angular_values.append(_number(frame.get("angular_velocity_rad_s", 0.0)))
		a_force_values.append(_force(frame, "A").length())
		b_force_values.append(_force(frame, "B").length())
	var min_time: float = _minimum_number(times, -2000.0)
	var max_time: float = _maximum_number(times, 2000.0)
	var all_values: Array[float] = error_values.duplicate()
	all_values.append_array(speed_values)
	all_values.append_array(angular_values)
	all_values.append_array(a_force_values)
	all_values.append_array(b_force_values)
	all_values.append_array(projections)
	var min_value: float = minf(_minimum_number(all_values, -1.0), -1.0)
	var max_value: float = maxf(_maximum_number(all_values, 1.0), 1.0)
	var svg: String = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	svg += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1000\" height=\"620\" viewBox=\"0 0 1000 620\">\n"
	svg += "<rect width=\"1000\" height=\"620\" fill=\"#fffdf6\"/>\n"
	svg += "<text x=\"70\" y=\"32\" font-family=\"sans-serif\" font-size=\"20\">%s</text>\n" % _xml_escape(perturbation_id)
	svg += "<line x1=\"%.3f\" y1=\"%.3f\" x2=\"%.3f\" y2=\"%.3f\" stroke=\"#444\"/>\n" % [left, bottom, right, bottom]
	svg += "<line x1=\"%.3f\" y1=\"%.3f\" x2=\"%.3f\" y2=\"%.3f\" stroke=\"#444\"/>\n" % [left, top, left, bottom]
	var onset_x: float = _map_value(0.0, min_time, max_time, left, right)
	svg += "<line x1=\"%.3f\" y1=\"%.3f\" x2=\"%.3f\" y2=\"%.3f\" stroke=\"#8e44ad\" stroke-dasharray=\"6 5\"/>\n" % [onset_x, top, onset_x, bottom]
	if perturbation.get("compensation_onset_ms") != null:
		var compensation_relative: float = (
			_number(perturbation["compensation_onset_ms"]) - onset
		)
		var compensation_x: float = _map_value(compensation_relative, min_time, max_time, left, right)
		svg += "<line x1=\"%.3f\" y1=\"%.3f\" x2=\"%.3f\" y2=\"%.3f\" stroke=\"#117864\" stroke-dasharray=\"3 4\"/>\n" % [compensation_x, top, compensation_x, bottom]
	if perturbation.get("recovery_time_ms") != null:
		var recovery_x: float = _map_value(
			_number(perturbation["recovery_time_ms"]), min_time, max_time, left, right
		)
		svg += "<line x1=\"%.3f\" y1=\"%.3f\" x2=\"%.3f\" y2=\"%.3f\" stroke=\"#2e86c1\" stroke-dasharray=\"3 4\"/>\n" % [recovery_x, top, recovery_x, bottom]
	svg += _svg_polyline(times, error_values, min_time, max_time, min_value, max_value, left, right, top, bottom, "#d35400")
	svg += _svg_polyline(times, speed_values, min_time, max_time, min_value, max_value, left, right, top, bottom, "#2471a3")
	svg += _svg_polyline(times, angular_values, min_time, max_time, min_value, max_value, left, right, top, bottom, "#7d3c98")
	svg += _svg_polyline(times, a_force_values, min_time, max_time, min_value, max_value, left, right, top, bottom, "#ca6f1e")
	svg += _svg_polyline(times, b_force_values, min_time, max_time, min_value, max_value, left, right, top, bottom, "#148f77")
	svg += _svg_polyline(times, projections, min_time, max_time, min_value, max_value, left, right, top, bottom, "#1e8449")
	svg += "<text x=\"75\" y=\"600\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#d35400\">signed error</text>"
	svg += "<text x=\"220\" y=\"600\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#2471a3\">speed</text>"
	svg += "<text x=\"290\" y=\"600\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#7d3c98\">angular</text>"
	svg += "<text x=\"365\" y=\"600\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#ca6f1e\">A force</text>"
	svg += "<text x=\"435\" y=\"600\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#148f77\">B force</text>"
	svg += "<text x=\"505\" y=\"600\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#1e8449\">compensation projection</text>"
	svg += "</svg>\n"
	file.store_string(svg)
	file.close()
	return true

static func _svg_polyline(
	times: Array[float], values: Array[float],
	min_time: float, max_time: float, min_value: float, max_value: float,
	left: float, right: float, top: float, bottom: float, color: String,
) -> String:
	var points: PackedStringArray = PackedStringArray()
	for i: int in mini(times.size(), values.size()):
		points.append("%.3f,%.3f" % [
			_map_value(times[i], min_time, max_time, left, right),
			_map_value(values[i], min_value, max_value, bottom, top),
		])
	return "<polyline fill=\"none\" stroke=\"%s\" stroke-width=\"2\" points=\"%s\"/>\n" % [
		color, " ".join(points),
	]

static func review_agreement(
	queue: Array[Dictionary], session_id: String, protocol: ExperimentProtocol
) -> Dictionary:
	var reviewed: int = 0
	var classification_matches: int = 0
	var onset_matches: int = 0
	var onset_differences: Array[float] = []
	var recovery_differences: Array[float] = []
	for row: Dictionary in queue:
		if str(row.get("manual_valid", "")).is_empty():
			continue
		reviewed += 1
		var automatic_valid: bool = _truthy(row.get("automatic_valid", false))
		var manual_valid: bool = _truthy(row.get("manual_valid", false))
		if automatic_valid == manual_valid:
			classification_matches += 1
		if not str(row.get("manual_onset_ms", "")).is_empty() and not str(row.get("automatic_onset_ms", "")).is_empty():
			var onset_difference: float = _number(row["manual_onset_ms"]) - _number(row["automatic_onset_ms"])
			onset_differences.append(onset_difference)
			if absf(onset_difference) <= protocol.manual_onset_tolerance_ms:
				onset_matches += 1
		if not str(row.get("manual_recovery_ms", "")).is_empty() and not str(row.get("automatic_recovery_ms", "")).is_empty():
			recovery_differences.append(
				_number(row["manual_recovery_ms"]) - _number(row["automatic_recovery_ms"])
			)
	return {
		"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
		"session_id": session_id,
		"reviewed_count": reviewed,
		"classification_agreement_rate": (
			float(classification_matches) / reviewed if reviewed > 0 else null
		),
		"onset_within_tolerance_rate": (
			float(onset_matches) / onset_differences.size()
			if not onset_differences.is_empty() else null
		),
		"onset_difference_mean_ms": _mean(onset_differences),
		"onset_difference_median_ms": _percentile(onset_differences, 0.5),
		"recovery_difference_mean_ms": _mean(recovery_differences),
		"recovery_difference_median_ms": _percentile(recovery_differences, 0.5),
	}

static func _write_result_csv(
	directory: String,
	filename: String,
	columns: PackedStringArray,
	rows: Array,
	outputs: Dictionary,
) -> bool:
	var path: String = directory.path_join(filename)
	var typed_rows: Array[Dictionary] = []
	for item: Variant in rows:
		if item is Dictionary:
			typed_rows.append(item as Dictionary)
	if typed_rows.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		outputs[filename] = {"rows": 0, "status": "omitted"}
		return true
	outputs[filename] = {"rows": typed_rows.size(), "status": "written"}
	return _write_csv(path, columns, typed_rows)

static func _write_manifest(
	path: String, session: Dictionary, protocol: ExperimentProtocol, outputs: Dictionary
) -> bool:
	var thresholds: Dictionary = {}
	var meta: Dictionary = protocol.metadata()
	for key: Variant in meta:
		thresholds[str(key)] = meta[key]
	return _write_json(path, {
		"schema_version": str(session.get("schema_version", "")),
		"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
		"session_id": str(session.get("session_id", "")),
		"generated_utc": Time.get_datetime_string_from_system(true, false),
		"thresholds": thresholds,
		"outputs": outputs,
	})

static func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

static func _write_csv(
	path: String, columns: PackedStringArray, rows: Array[Dictionary]
) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var header: Array[Variant] = []
	for column: String in columns:
		header.append(column)
	file.store_string(_csv_row(header) + "\r\n")
	for row: Dictionary in rows:
		var values: Array[Variant] = []
		for column: String in columns:
			values.append(row.get(column, ""))
		file.store_string(_csv_row(values) + "\r\n")
	file.flush()
	file.close()
	return true

static func _read_csv(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		return rows
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0:
		return rows
	var header: PackedStringArray = file.get_csv_line()
	while file.get_position() < file.get_length():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() != header.size():
			continue
		var row: Dictionary = {}
		for i: int in header.size():
			row[header[i]] = values[i]
		rows.append(row)
	file.close()
	return rows

static func _sustained_start(
	frames: Array[Dictionary], participant: String,
	protocol: ExperimentProtocol, force_scale: float,
) -> Variant:
	var candidate: float = -1.0
	for frame: Dictionary in frames:
		var time_ms: float = _number(frame.get("trial_elapsed_ms", 0.0))
		if _force(frame, participant).length() / force_scale > protocol.activity_threshold:
			if candidate < 0.0:
				candidate = time_ms
			if time_ms + _frame_delta_ms(frame) - candidate >= protocol.sustained_start_ms:
				return candidate
		else:
			candidate = -1.0
	return null

static func _smooth_force(
	frames: Array[Dictionary], participant: String, radius: int
) -> Array[Vector2]:
	var output: Array[Vector2] = []
	for i: int in frames.size():
		var sum := Vector2.ZERO
		var count: int = 0
		for j: int in range(maxi(0, i - radius), mini(frames.size(), i + radius + 1)):
			sum += _force(frames[j], participant)
			count += 1
		output.append(sum / maxf(float(count), 1.0))
	return output

static func _set_ineligible_perturbation(result: Dictionary, status: String) -> void:
	result["compensation_status"] = status
	result["compensation_onset_ms"] = null
	result["compensation_reaction_ms"] = null
	result["compensation_peak_projection"] = null
	result["recovery_status"] = status
	result["recovery_time_ms"] = null
	result["recovery_stable_time_ms"] = null
	result["recovery_observation_ms"] = null
	result["recovery_censored"] = 0
	result["overshoot_status"] = status
	result["overshoot_first_reverse_max"] = null
	result["overcompensation_index"] = null
	result["overshoot_round_trips"] = 0

static func _filter_trial(rows: Array[Dictionary], trial_id: String) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for row: Dictionary in rows:
		if str(row.get("trial_id", "")) == trial_id:
			selected.append(row)
	selected.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _number(a.get("trial_elapsed_ms", 0.0)) < _number(b.get("trial_elapsed_ms", 0.0))
	)
	return selected

static func _window(rows: Array[Dictionary], start_ms: float, end_ms: float) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for row: Dictionary in rows:
		var time_ms: float = _number(row.get("trial_elapsed_ms", 0.0))
		if time_ms >= start_ms and time_ms <= end_ms:
			selected.append(row)
	return selected

static func _nearest_frame(frames: Array[Dictionary], time_ms: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for frame: Dictionary in frames:
		var distance: float = absf(_number(frame.get("trial_elapsed_ms", 0.0)) - time_ms)
		if distance < best_distance:
			best_distance = distance
			best = frame
	return best

static func _force(frame: Dictionary, participant: String) -> Vector2:
	return Vector2(
		_number(frame.get("%s_force_x" % participant, 0.0)),
		_number(frame.get("%s_force_y" % participant, 0.0))
	)

static func _frame_delta_ms(frame: Dictionary) -> float:
	return maxf(_number(frame.get("physics_delta_s", 0.0)) * 1000.0, 0.0)

static func _median_delta_ms(frames: Array[Dictionary]) -> float:
	var deltas: Array[float] = []
	for frame: Dictionary in frames:
		var delta: float = _frame_delta_ms(frame)
		if delta > 0.0:
			deltas.append(delta)
	var median: Variant = _percentile(deltas, 0.5)
	return float(median) if median != null else 16.666667

static func _median_field(rows: Array[Dictionary], field: String) -> float:
	var median: Variant = _percentile(_field_values(rows, field), 0.5)
	return float(median) if median != null else 0.0

static func _field_values(
	rows: Array[Dictionary], field: String, absolute: bool = false
) -> Array[float]:
	var values: Array[float] = []
	for row: Dictionary in rows:
		var value: float = _number(row.get(field, 0.0))
		values.append(absf(value) if absolute else value)
	return values

static func _first_value(
	frames: Array[Dictionary], events: Array[Dictionary], field: String
) -> Variant:
	if not frames.is_empty():
		return frames[0].get(field, "")
	if not events.is_empty():
		return events[0].get(field, "")
	return ""

static func _count_event(events: Array[Dictionary], event_type: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if str(event.get("event_type", "")) == event_type:
			count += 1
	return count

static func _event_time(events: Array[Dictionary], event_type: String) -> Variant:
	for event: Dictionary in events:
		if str(event.get("event_type", "")) == event_type:
			return _number(event.get("trial_elapsed_ms", 0.0))
	return null

static func _trial_outcome(events: Array[Dictionary]) -> String:
	for i: int in range(events.size() - 1, -1, -1):
		if str(events[i].get("event_type", "")) == "trial_end":
			return str(events[i].get("outcome", ""))
	return "incomplete"

static func _last_time_ms(frames: Array[Dictionary], events: Array[Dictionary]) -> float:
	var value: float = 0.0
	if not frames.is_empty():
		value = maxf(value, _number(frames[-1].get("trial_elapsed_ms", 0.0)))
	if not events.is_empty():
		value = maxf(value, _number(events[-1].get("trial_elapsed_ms", 0.0)))
	return value

static func _mean(values: Array[float]) -> Variant:
	if values.is_empty():
		return null
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / values.size()

static func _percentile(values: Array[float], percentile: float) -> Variant:
	if values.is_empty():
		return null
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var position: float = clampf(percentile, 0.0, 1.0) * float(sorted.size() - 1)
	var lower: int = int(floor(position))
	var upper: int = int(ceil(position))
	if lower == upper:
		return sorted[lower]
	var fraction: float = position - lower
	return lerpf(sorted[lower], sorted[upper], fraction)

static func _maximum(values: Array[float]) -> Variant:
	return _maximum_number(values, NAN) if not values.is_empty() else null

static func _minimum_number(values: Array[float], fallback: float) -> float:
	if values.is_empty():
		return fallback
	var result: float = values[0]
	for value: float in values:
		result = minf(result, value)
	return result

static func _maximum_number(values: Array[float], fallback: float) -> float:
	if values.is_empty():
		return fallback
	var result: float = values[0]
	for value: float in values:
		result = maxf(result, value)
	return result

static func _number(value: Variant) -> float:
	if value == null:
		return 0.0
	if value is float or value is int:
		return float(value)
	var text: String = str(value)
	return text.to_float() if text.is_valid_float() else 0.0

static func _truthy(value: Variant) -> bool:
	if value is bool:
		return bool(value)
	return str(value).strip_edges().to_lower() in ["1", "true", "yes", "y"]

static func _map_value(
	value: float, input_min: float, input_max: float, output_min: float, output_max: float
) -> float:
	if is_equal_approx(input_min, input_max):
		return (output_min + output_max) * 0.5
	return remap(value, input_min, input_max, output_min, output_max)

static func _safe_filename(value: String) -> String:
	var output: String = ""
	for character: String in value:
		output += character if character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-" else "_"
	return output

static func _xml_escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

## 与原始 logger 的 RFC4180 规则保持字节级兼容，同时维持纯模块无 autoload 依赖。
static func _csv_row(values: Array[Variant]) -> String:
	var escaped: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		var text: String = ""
		if value != null:
			if value is bool:
				text = "1" if bool(value) else "0"
			elif value is float:
				text = String.num(float(value), 9)
			else:
				text = str(value)
		if text.contains("\""):
			text = text.replace("\"", "\"\"")
		if text.contains(",") or text.contains("\"") or text.contains("\r") or text.contains("\n"):
			text = "\"%s\"" % text
		escaped.append(text)
	return ",".join(escaped)
