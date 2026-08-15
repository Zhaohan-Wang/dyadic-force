extends SceneTree
## 合成确定性验证：基础协作、已知 lag、补偿、恢复、删失、过补偿与复核抽样。

const SESSION_TEST_COLUMNS: PackedStringArray = [
	"session_id", "dyad_id", "participant_A", "participant_B",
	"relation_condition", "side_assignment", "force_max",
	"physics_ticks_per_second",
]
const FRAME_TEST_COLUMNS: PackedStringArray = [
	"session_id", "trial_id", "life_id", "level_id", "level_attempt_index",
	"protocol_version", "trial_elapsed_ms", "physics_delta_s", "A_slot", "B_slot",
	"A_force_x", "A_force_y", "B_force_x", "B_force_y", "core_x", "core_y",
	"route_error_x", "route_error_y", "route_signed_error", "route_error_distance",
	"route_max_progress", "inside_boundary", "speed", "angular_velocity_rad_s",
]
const EVENT_TEST_COLUMNS: PackedStringArray = [
	"session_id", "trial_id", "life_id", "level_id", "level_attempt_index",
	"protocol_version", "trial_elapsed_ms", "event_type", "slot", "gain", "outcome",
]

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var protocol := ExperimentProtocol.new()
	protocol.force_smoothing_ms = 40.0
	protocol.cross_correlation_min_active_ms = 300.0
	_test_trial_metrics(protocol)
	_test_invalid_and_quality_metrics(protocol)
	_test_perturbation_metrics(protocol)
	_test_censoring(protocol)
	_test_review_package(protocol)
	if _failures.is_empty():
		print("BEHAVIOR_METRICS_ASSERT_OK")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _test_trial_metrics(protocol: ExperimentProtocol) -> void:
	var frames: Array[Dictionary] = []
	var force_series: Array[float] = []
	for i: int in 101:
		force_series.append(0.0 if i < 5 else 0.45 + 0.12 * sin(float(i * i) * 0.17))
	for i: int in 101:
		var a_force: float = force_series[i]
		var b_force: float = force_series[i - 5] if i >= 5 else 0.0
		frames.append(_frame(i * 20.0, a_force, 0.0, b_force, 0.0, 8.0, 8.0))
	var events: Array[Dictionary] = [
		_event(0.0, "run_start"),
		_event(2000.0, "trial_end", "success"),
	]
	var result: Dictionary = ExperimentAnalyzer.analyze_trial(frames, events, protocol, 1.0)
	_expect_close(result["direction_cosine_mean"], 1.0, 0.001, "direction cosine")
	_expect(float(result["direction_valid_ms"]) > 1500.0, "direction valid duration")
	_expect(result["startup_status"] == "ok", "startup status")
	_expect_close(result["startup_difference_ms"], 100.0, 20.1, "100ms startup difference")
	_expect(result["xcorr_status"] == "ok", "cross correlation status")
	_expect_close(result["xcorr_lag_ms"], 100.0, 20.1, "known cross correlation lag")
	_expect(result["xcorr_leader"] == "A", "cross correlation leader")

	var conflict_frames: Array[Dictionary] = []
	for i: int in 20:
		conflict_frames.append(_frame(i * 20.0, 0.6, 0.0, -0.6, 0.0, 5.0, 5.0))
	var conflict: Dictionary = ExperimentAnalyzer.analyze_trial(
		conflict_frames, events, protocol, 1.0
	)
	_expect_close(conflict["conflict_ratio"], 1.0, 0.001, "conflict ratio")
	_expect_close(conflict["intensity_difference_mean"], 0.0, 0.001, "intensity difference")

func _test_invalid_and_quality_metrics(protocol: ExperimentProtocol) -> void:
	var frames: Array[Dictionary] = []
	for i: int in 5:
		var frame: Dictionary = _frame(
			i * 20.0, 0.5, 0.0, 0.5, 0.0, 5.0, 5.0
		)
		frame["render_fps"] = 60.0
		frame["A_connected"] = 1
		frame["B_connected"] = 1
		frames.append(frame)
	frames[-1]["physics_delta_s"] = 0.06
	frames[-1]["system_quality"] = "late"
	var quit_end: Dictionary = _event(100.0, "trial_end", "quit")
	quit_end["note"] = "level_select_requested"
	var result: Dictionary = ExperimentAnalyzer.analyze_trial(
		frames, [quit_end], protocol, 1.0, 60.0
	)
	_expect(result["quit_reason"] == "level_select_requested", "quit reason")
	_expect(result["intensity_difference_mean"] == null, "quit intensity must be missing")
	_expect(
		result["route_correction_integral_A"] == null,
		"quit correction integral must be missing",
	)
	_expect_close(result["mean_render_fps"], 60.0, 0.01, "mean render fps")
	_expect_close(result["mean_physics_delta_ms"], 28.0, 0.01, "mean physics delta")
	_expect(
		float(result["estimated_frame_drop_pct"]) > 5.0,
		"estimated frame drop percentage",
	)
	_expect(str(result["quality_flag"]).contains("high_frame_drop"), "frame-drop QC flag")

func _test_perturbation_metrics(protocol: ExperimentProtocol) -> void:
	var frames: Array[Dictionary] = []
	for i: int in 111:
		var time_ms: float = i * 20.0
		var signed_error: float = 10.0
		var distance: float = 10.0
		var speed: float = 1.0
		var angular: float = 0.05
		var b_force_x: float = 0.0
		if time_ms >= 400.0 and time_ms < 900.0:
			signed_error = 12.0
			distance = 12.0
			speed = 20.0
			angular = 1.0
		if time_ms >= 500.0:
			b_force_x = -0.35
		if time_ms >= 900.0 and time_ms < 1200.0:
			signed_error = -5.0
			distance = 5.0
			speed = 12.0
			angular = 0.5
		elif time_ms >= 1200.0:
			signed_error = 10.0
			distance = 10.0
			speed = 1.0
			angular = 0.05
		var frame: Dictionary = _frame(
			time_ms, 0.3, 0.0, b_force_x, 0.0, distance, signed_error
		)
		frame["speed"] = speed
		frame["angular_velocity_rad_s"] = angular
		frames.append(frame)
	var event: Dictionary = _event(400.0, "perturb_on")
	event["slot"] = 0
	event["gain"] = 0.5
	var result: Dictionary = ExperimentAnalyzer.analyze_perturbation(
		frames, event, 1800.0, protocol, 1.0
	)
	_expect(result["perturbed_participant"] == "A", "perturbed slot mapping")
	_expect(result["compensation_status"] == "valid", "valid compensation")
	_expect_close(result["compensation_reaction_ms"], 100.0, 20.1, "compensation reaction")
	_expect(result["recovery_status"] == "recovered", "500ms recovery")
	_expect_close(result["recovery_time_ms"], 800.0, 20.1, "recovery onset")
	_expect_close(result["recovery_stable_time_ms"], 800.0, 20.1, "recovery analysis time")
	_expect(result["overshoot_status"] == "overshoot", "overshoot detection")
	_expect_close(
		result["overcompensation_index"], 0.5, 0.01, "overcompensation index"
	)
	_expect(int(result["overshoot_round_trips"]) == 1, "overshoot round trip")

func _test_censoring(protocol: ExperimentProtocol) -> void:
	var frames: Array[Dictionary] = []
	for i: int in 36:
		frames.append(_frame(i * 20.0, 0.3, 0.0, 0.0, 0.0, 10.0, 10.0))
	var event: Dictionary = _event(400.0, "perturb_on")
	event["slot"] = 0
	var result: Dictionary = ExperimentAnalyzer.analyze_perturbation(
		frames, event, 700.0, protocol, 1.0
	)
	_expect(result["compensation_status"] == "censored", "compensation censoring")
	_expect(int(result["recovery_censored"]) == 1, "recovery censoring")
	_expect_close(
		result["recovery_stable_time_ms"], 300.0, 20.1,
		"censored recovery observation limit",
	)

func _test_review_package(protocol: ExperimentProtocol) -> void:
	var root: String = "user://behavior_metrics_assert"
	var user_dir: DirAccess = DirAccess.open("user://")
	if DirAccess.dir_exists_absolute(root):
		_remove_tree(root)
	user_dir.make_dir("behavior_metrics_assert")
	_write_rows(
		root.path_join("session.csv"),
		SESSION_TEST_COLUMNS,
		[[
			"FIXED_SESSION", "S9-D001", "S9-D001-A", "S9-D001-B",
			"friends", "A=P1;B=P2", 1.0, 60,
		]],
	)

	var frame_rows: Array[Array] = []
	for i: int in 21:
		var row: Array[Variant] = []
		var data: Dictionary = _frame(i * 100.0, 0.3, 0.0, 0.3, 0.0, 10.0, 10.0)
		data["session_id"] = "FIXED_SESSION"
		data["trial_id"] = "FIXED_SESSION-T0001"
		data["level_id"] = "synthetic"
		for column: String in FRAME_TEST_COLUMNS:
			row.append(data.get(column, ""))
		frame_rows.append(row)
	_write_rows(root.path_join("frames.csv"), FRAME_TEST_COLUMNS, frame_rows)

	var event_rows: Array[Array] = []
	for i: int in 10:
		var on: Dictionary = _event(200.0 + i * 150.0, "perturb_on")
		on["session_id"] = "FIXED_SESSION"
		on["trial_id"] = "FIXED_SESSION-T0001"
		on["level_id"] = "synthetic"
		on["slot"] = i % 2
		on["gain"] = 0.5
		var off: Dictionary = on.duplicate()
		off["trial_elapsed_ms"] = 260.0 + i * 150.0
		off["event_type"] = "perturb_off"
		for data: Dictionary in [on, off]:
			var row: Array[Variant] = []
			for column: String in EVENT_TEST_COLUMNS:
				row.append(data.get(column, ""))
			event_rows.append(row)
	_write_rows(root.path_join("events.csv"), EVENT_TEST_COLUMNS, event_rows)
	var paths: Dictionary = {
		"directory": root,
		"session": root.path_join("session.csv"),
		"frames": root.path_join("frames.csv"),
		"events": root.path_join("events.csv"),
		"results_directory": root.path_join("results"),
		"qc_directory": root.path_join("qc"),
	}
	_expect(ExperimentAnalyzer.export_session(paths, protocol), "default result export")
	_expect(
		not FileAccess.file_exists(root.path_join("qc").path_join("review_queue.csv")),
		"review queue should not be written by default export",
	)
	_expect(FileAccess.file_exists(root.path_join("results").path_join("trial_results.csv")), "trial_results missing")
	_expect(FileAccess.file_exists(root.path_join("results").path_join("perturbation_results.csv")), "perturbation_results missing")
	var trial_rows: Array[Dictionary] = ExperimentAnalyzer.read_csv(
		root.path_join("results").path_join("trial_results.csv")
	)
	_expect(not trial_rows.is_empty(), "trial summary unreadable")
	if not trial_rows.is_empty():
		var trial: Dictionary = trial_rows[0]
		_expect(trial.get("dyad_id") == "S9-D001", "trial identity not denormalized")
		_expect(int(trial.get("perturbation_count", 0)) == 10, "trial perturbation count")
		_expect(trial.get("perturbed_participants") == "A;B", "trial perturbed participants")
	_expect(ExperimentAnalyzer.export_review_package(paths, protocol), "first review package")
	var first_ids: PackedStringArray = _review_ids(root.path_join("qc").path_join("review_queue.csv"))
	_expect(first_ids.size() >= 2, "at least 20 percent review sample")
	_expect(ExperimentAnalyzer.export_review_package(paths, protocol), "second review package")
	var second_ids: PackedStringArray = _review_ids(root.path_join("qc").path_join("review_queue.csv"))
	_expect(first_ids == second_ids, "fixed-seed review sample")
	_expect(
		not FileAccess.file_exists(root.path_join("qc").path_join("review_windows.csv")),
		"review_windows.csv should not be generated",
	)
	for perturbation_id: String in first_ids:
		_expect(
			FileAccess.file_exists(root.path_join("qc").path_join("review_%s.svg" % perturbation_id)),
			"review SVG missing",
		)

func _frame(
	time_ms: float,
	a_x: float,
	a_y: float,
	b_x: float,
	b_y: float,
	error_distance: float,
	signed_error: float,
) -> Dictionary:
	return {
		"schema_version": "3.1.0", "session_id": "S", "trial_id": "S-T0001",
		"life_id": "S-T0001-L001", "level_id": "synthetic",
		"level_attempt_index": 1, "protocol_version": "pilot-1.0",
		"trial_elapsed_ms": time_ms, "physics_delta_s": 0.02,
		"A_slot": 0, "B_slot": 1,
		"A_force_x": a_x, "A_force_y": a_y,
		"B_force_x": b_x, "B_force_y": b_y,
		"core_x": time_ms * 0.01, "core_y": signed_error,
		"route_error_x": error_distance, "route_error_y": 0.0,
		"route_signed_error": signed_error,
		"route_error_distance": error_distance,
		"route_max_progress": time_ms / 2200.0,
		"inside_boundary": true, "speed": 1.0,
		"angular_velocity_rad_s": 0.05,
	}

func _event(time_ms: float, event_type: String, outcome: String = "") -> Dictionary:
	return {
		"schema_version": "3.1.0", "session_id": "S", "trial_id": "S-T0001",
		"life_id": "S-T0001-L001", "level_id": "synthetic",
		"level_attempt_index": 1, "protocol_version": "pilot-1.0",
		"trial_elapsed_ms": time_ms, "event_type": event_type, "outcome": outcome,
	}

func _write_rows(
	path: String, columns: PackedStringArray, rows: Array
) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var header: Array[Variant] = []
	for column: String in columns:
		header.append(column)
	file.store_string(_csv_row(header) + "\r\n")
	for row: Array in rows:
		file.store_string(_csv_row(row) + "\r\n")
	file.close()

func _csv_row(values: Array[Variant]) -> String:
	var escaped: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		var text: String = str(value)
		if text.contains("\""):
			text = text.replace("\"", "\"\"")
		if text.contains(",") or text.contains("\"") or text.contains("\r") or text.contains("\n"):
			text = "\"%s\"" % text
		escaped.append(text)
	return ",".join(escaped)

func _review_ids(path: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ids
	var header: PackedStringArray = file.get_csv_line()
	var index: int = header.find("perturbation_id")
	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == header.size():
			ids.append(row[index])
	file.close()
	return ids

func _expect_close(value: Variant, expected: float, tolerance: float, label: String) -> void:
	_expect(value != null and absf(float(value) - expected) <= tolerance, "%s mismatch: %s" % [label, value])

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for filename: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
