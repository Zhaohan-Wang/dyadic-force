extends SceneTree
## 数据验证终局回归：生命周期、不可覆盖、时钟/CSV、断连、flush、自动派生与中断恢复。

const RECOVERY_ROOT: String = "user://data_validation_recovery"
const RECOVERY_SESSION: String = RECOVERY_ROOT + "/CASE"

var _failures: PackedStringArray = PackedStringArray()
var _log
var _game_state

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_log = root.get_node_or_null("ExperimentLog")
	_game_state = root.get_node_or_null("GameState")
	if _log == null:
		_fail("ExperimentLog autoload missing")
		_finish()
		return
	if _game_state == null:
		_fail("GameState autoload missing")
		_finish()
		return
	_prepare_identity()
	var level_def: LevelDef = load("res://levels/practice.tres") as LevelDef
	if level_def == null:
		_fail("practice level missing")
		_finish()
		return

	var ball: RigidBody2D = RigidBody2D.new()
	root.add_child(ball)
	await physics_frame

	# 成功试次覆盖碰撞死亡、重生、暂停、断连、扰动与自动 SVG 导出。
	_expect(_log.begin_trial(level_def, "perturbation"), "success trial did not start")
	var first: Dictionary = _log.summary_dict()
	var session_rows: Array[Dictionary] = _read_csv_checked(str(first["log_session"]))
	_expect(
		not session_rows.is_empty() and not str(session_rows[0].get("app_version", "")).is_empty(),
		"session app_version was empty",
	)
	_log.log_event("run_start")
	_log.log_event("collision", {"impact_strength": 4.5})
	_log.log_event("damage", {"damage": 1.0, "remaining_hp": 0.0})
	_log.log_event("death_collision", {"damage": 1.0, "remaining_hp": 0.0})
	_log.log_event("respawn_start")
	_log.begin_life("validation_respawn")
	var respawn_life: String = str(_log.summary_dict()["life_id"])
	_expect(respawn_life != str(first["life_id"]), "life_id did not increment on respawn")
	_log.log_event("pause")
	_log.log_event("resume")
	_log.call("_on_joy_hotplug", 77, false)
	_log.log_event("perturb_on", {"slot": 0, "gain": 0.5, "note": "csv,\"quote\"\nline"})
	for i: int in 4:
		await physics_frame
		ball.position = Vector2(float(i), float(i % 2))
		_log.log_frame(1.0 / 60.0, "running", ball)
	_log.log_event("perturb_off", {"slot": 0, "gain": 1.0})
	_log.log_event("success", {"outcome": "success"})
	_expect(_log.end_trial("success"), "automatic derived export failed after success")
	var saved: Dictionary = _log.summary_dict()
	_expect(bool(saved["data_export_ok"]), "saved status was not exposed")
	_expect(str(saved["data_export_message"]) == "saved", "saved status message mismatch")
	_assert_derived_outputs(saved)
	await _assert_results_data_entry(saved)

	# 同关重试必须共享 session/raw 文件但使用全新 trial_id 与递增 attempt。
	_expect(_log.begin_trial(level_def, "baseline"), "timeout trial did not start")
	var second: Dictionary = _log.summary_dict()
	_expect(first["session_id"] == second["session_id"], "same run changed session_id")
	_expect(first["trial_id"] != second["trial_id"], "same-level retry reused trial_id")
	_expect(first["log_events"] == second["log_events"], "same-level retry changed raw event path")
	_log.log_event("run_start")
	_log.log_event("timeout_failure", {"outcome": "timeout"})
	_expect(_log.end_trial("timeout"), "automatic derived export failed after timeout")

	_expect(_log.begin_trial(level_def, "baseline"), "restart trial did not start")
	_log.log_event("restart_requested")
	_expect(_log.end_trial("restarted"), "automatic derived export failed after restart")

	_expect(_log.begin_trial(level_def, "baseline"), "quit trial did not start")
	_log.log_event("quit_mid_trial")
	_expect(_log.end_trial("quit"), "automatic derived export failed after quit")

	# 事件缓冲与 flush 压力代理：6000 行远高于一分钟 60 Hz 的离散事件量。
	_expect(_log.begin_trial(level_def, "baseline"), "flush trial did not start")
	var flush_start_us: int = Time.get_ticks_usec()
	for i: int in 6000:
		_log.log_event("flush_probe", {"note": i})
	_log.flush()
	var flush_elapsed_ms: float = float(Time.get_ticks_usec() - flush_start_us) / 1000.0
	_expect(flush_elapsed_ms < 5000.0, "6000-row buffer/flush exceeded 5s: %.2fms" % flush_elapsed_ms)
	_expect(_log.end_trial("restarted"), "automatic derived export failed after flush trial")

	# close_session 覆盖仍活跃试次的 app_abort + aborted trial_end。
	_expect(_log.begin_trial(level_def, "baseline"), "abort trial did not start")
	_log.log_event("run_start")
	_log.close_session()
	ball.queue_free()

	var events_path: String = str(first["log_events"])
	var frames_path: String = str(first["log_samples"])
	var events: Array[Dictionary] = _read_csv_checked(events_path)
	var frames: Array[Dictionary] = _read_csv_checked(frames_path)
	_assert_lifecycle(events)
	_assert_clock(events, "events")
	_assert_clock(frames, "frames")
	_assert_shared_clock_domain(events, frames)
	_assert_attempts(events)

	_test_interruption_recovery()
	_finish()

func _prepare_identity() -> void:
	_game_state.set("experiment_mode", true)
	_game_state.set("dyad_id", "S1-D001")
	_game_state.set("participant_A", "S1-D001-A")
	_game_state.set("participant_B", "S1-D001-B")
	_game_state.set("relation_condition", "friends")
	_game_state.set("protocol_version", "pilot-1.0")
	_game_state.set("participant_a_slot", 0)
	_game_state.set("side_assignment", "A=P1;B=P2")
	_game_state.set("experiment_setup_locked", true)

func _assert_derived_outputs(summary: Dictionary) -> void:
	var results_dir: String = str(summary.get("results_directory", ""))
	_expect(not results_dir.is_empty(), "results_directory missing from summary")
	for filename: String in ["trial_results.csv", "perturbation_results.csv", "analysis_manifest.json"]:
		_expect(FileAccess.file_exists(results_dir.path_join(filename)), "%s missing" % filename)
	for filename: String in [
		"dyad_summary.csv", "analysis_metadata.csv", "review_queue.csv",
		"review_windows.csv", "review_agreement.csv", "gate_results.csv",
		"segment_results.csv", "choice_results.csv",
	]:
		_expect(
			not FileAccess.file_exists(results_dir.path_join(filename)),
			"unexpected default result: %s" % filename,
		)
	var qc_dir: String = str(summary.get("qc_directory", ""))
	_expect(
		not FileAccess.file_exists(qc_dir.path_join("review_queue.csv")),
		"review package should not be generated by default",
	)
	var manifest_file: FileAccess = FileAccess.open(results_dir.path_join("analysis_manifest.json"), FileAccess.READ)
	_expect(manifest_file != null, "analysis_manifest.json unreadable")
	if manifest_file != null:
		var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
		manifest_file.close()
		_expect(parsed is Dictionary, "analysis_manifest.json is not an object")
		if parsed is Dictionary:
			var manifest: Dictionary = parsed
			_expect(str(manifest.get("analysis_version", "")) == ExperimentProtocol.ANALYSIS_VERSION, "manifest analysis_version")
			var outputs: Dictionary = manifest.get("outputs", {}) as Dictionary
			_expect(str((outputs.get("trial_results.csv", {}) as Dictionary).get("status", "")) == "written", "trial_results not written")
			_expect(str((outputs.get("perturbation_results.csv", {}) as Dictionary).get("status", "")) == "written", "perturbation_results not written")
			_expect(str((outputs.get("gate_results.csv", {}) as Dictionary).get("status", "")) == "omitted", "empty gate table should be omitted")

func _assert_results_data_entry(summary: Dictionary) -> void:
	var result: Dictionary = summary.duplicate()
	result.merge({
		"success": false, "stars": 0, "level_id": "practice", "level_name": "TUTORIAL",
		"island": Vector2(100, 100), "spawn": Vector2.ZERO, "goal": Vector2(50, 0),
	}, false)
	_game_state.set("last_result", result)
	var packed: PackedScene = load("res://scenes/results_screen.tscn") as PackedScene
	_expect(packed != null, "results scene missing")
	if packed == null:
		return
	var page: Node = packed.instantiate()
	root.add_child(page)
	await process_frame
	var found_open: bool = false
	for node: Node in page.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.text in ["打开文件夹", "OPEN FOLDER"]:
			found_open = true
			_expect(not button.disabled, "data folder button was disabled for a valid directory")
	_expect(found_open, "results screen data folder entry missing")
	var found_path_leak: bool = false
	for node: Node in page.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label != null and (
			label.text.contains("/Users/")
			or label.text.contains("user://")
			or label.text.contains("\\")
		):
			found_path_leak = true
	_expect(not found_path_leak, "results screen should not display raw save paths")
	page.queue_free()
	await process_frame

func _assert_lifecycle(events: Array[Dictionary]) -> void:
	for event_type: String in [
		"trial_created", "run_start", "collision", "damage", "death_collision",
		"respawn_start", "respawn_end", "pause", "resume", "controller_disconnect",
		"perturb_on", "perturb_off", "success", "timeout_failure",
		"restart_requested", "quit_mid_trial", "app_abort", "trial_end",
	]:
		_expect(_has_event(events, event_type), "lifecycle event missing: %s" % event_type)
	var outcomes: PackedStringArray = PackedStringArray()
	for row: Dictionary in events:
		if str(row.get("event_type", "")) == "trial_end":
			outcomes.append(str(row.get("outcome", "")))
	for outcome: String in ["success", "timeout", "restarted", "quit", "aborted"]:
		_expect(outcomes.has(outcome), "trial outcome missing: %s" % outcome)

func _assert_clock(rows: Array[Dictionary], label: String) -> void:
	var previous: int = -1
	for row: Dictionary in rows:
		var now: int = int(str(row.get("monotonic_time_us", "0")))
		_expect(now > previous, "%s monotonic_time_us was not strictly increasing" % label)
		previous = now

func _assert_shared_clock_domain(events: Array[Dictionary], frames: Array[Dictionary]) -> void:
	var event_times: Dictionary = {}
	for row: Dictionary in events:
		event_times[str(row.get("monotonic_time_us", ""))] = true
	for row: Dictionary in frames:
		_expect(
			not event_times.has(str(row.get("monotonic_time_us", ""))),
			"frames/events did not share the strictly ordered clock generator",
		)
	for required: String in [
		"monotonic_time_us", "session_elapsed_ms", "trial_elapsed_ms",
		"physics_frame", "trial_id", "life_id",
	]:
		_expect(
			_log.schema_columns()["events"].has(required)
			and _log.schema_columns()["frames"].has(required),
			"shared clock column missing: %s" % required,
		)

func _assert_attempts(events: Array[Dictionary]) -> void:
	var attempts: Dictionary = {}
	var trial_ids: Dictionary = {}
	for row: Dictionary in events:
		if str(row.get("event_type", "")) != "trial_created":
			continue
		attempts[int(str(row.get("level_attempt_index", "0")))] = true
		trial_ids[str(row.get("trial_id", ""))] = true
	_expect(attempts.size() == 6, "expected six same-level attempt indices")
	_expect(trial_ids.size() == 6, "expected six unique trial IDs")
	for expected: int in range(1, 7):
		_expect(attempts.has(expected), "level_attempt_index missing: %d" % expected)

func _test_interruption_recovery() -> void:
	var user_dir: DirAccess = DirAccess.open("user://")
	_expect(user_dir != null, "cannot open user directory for recovery fixture")
	if user_dir == null:
		return
	user_dir.make_dir_recursive("data_validation_recovery/CASE/raw")
	var schema: Dictionary = _log.schema_columns()
	var session_columns: PackedStringArray = schema["session"]
	var frame_columns: PackedStringArray = schema["frames"]
	var event_columns: PackedStringArray = schema["events"]
	var raw_dir: String = RECOVERY_SESSION.path_join("raw")
	_write_fixture_csv(
		raw_dir.path_join("session.csv"),
		session_columns,
		{"schema_version": schema["schema_version"], "session_id": "RECOVER_CASE", "force_max": 1.0},
	)
	_write_fixture_csv(raw_dir.path_join("frames.csv"), frame_columns, {})
	_write_fixture_csv(
		raw_dir.path_join("events.csv"),
		event_columns,
		{
			"schema_version": schema["schema_version"], "session_id": "RECOVER_CASE",
			"monotonic_time_us": 100, "session_elapsed_ms": 1,
			"trial_elapsed_ms": 1, "physics_frame": 1,
			"trial_id": "RECOVER_CASE-T0001", "life_id": "RECOVER_CASE-T0001-L001",
			"level_id": "practice", "level_attempt_index": 1,
			"protocol_version": "pilot-1.0", "event_type": "run_start",
		},
	)
	_log.call("_recover_interrupted_sessions", RECOVERY_ROOT)
	var recovered: Array[Dictionary] = _read_csv_checked(
		raw_dir.path_join("events.csv")
	)
	_expect(_has_event(recovered, "aborted_recovered"), "recovery marker missing")
	_expect(_has_event(recovered, "trial_end"), "recovered trial_end missing")
	_expect(
		FileAccess.file_exists(RECOVERY_SESSION.path_join("results").path_join("trial_results.csv")),
		"recovery did not regenerate trial_results.csv",
	)

func _write_fixture_csv(path: String, columns: PackedStringArray, row: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "cannot write fixture: %s" % path)
	if file == null:
		return
	var header: Array[Variant] = []
	var values: Array[Variant] = []
	for column: String in columns:
		header.append(column)
		values.append(row.get(column, ""))
	file.store_string(_log.csv_row(header) + "\r\n")
	if not row.is_empty():
		file.store_string(_log.csv_row(values) + "\r\n")
	file.close()

func _read_csv_checked(path: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "CSV missing: %s" % path)
	if file == null:
		return output
	var header: PackedStringArray = file.get_csv_line()
	_expect(not header.is_empty(), "CSV header missing: %s" % path)
	while file.get_position() < file.get_length():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and values[0].is_empty():
			continue
		_expect(values.size() == header.size(), "RFC4180 parse column mismatch: %s" % path)
		if values.size() != header.size():
			continue
		var row: Dictionary = {}
		for i: int in header.size():
			row[header[i]] = values[i]
		output.append(row)
	file.close()
	return output

func _has_event(rows: Array[Dictionary], event_type: String) -> bool:
	for row: Dictionary in rows:
		if str(row.get("event_type", "")) == event_type:
			return true
	return false

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("DATA_VALIDATION_ASSERT_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
