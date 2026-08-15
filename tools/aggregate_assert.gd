extends SceneTree
## 跨组汇总回归：按需文件、身份 join、主键、版本冲突与空值规则。
const Aggregator := preload("res://scripts/experiment/experiment_aggregator.gd")

const ROOT: String = "user://aggregate_assert"
const OUT: String = "user://aggregate_assert/_aggregate"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_reset_root()
	var first: Dictionary = _write_session(
		"S1-D001",
		"2026-08-15_000001Z",
		"pilot-1.0",
		[
			{"trial": "T0001", "level": "unsteady_trail", "perturb": true, "gate": false},
			{"trial": "T0002", "level": "unsteady_trail", "perturb": true, "gate": false},
		]
	)
	var second: Dictionary = _write_session(
		"S1-D002",
		"2026-08-15_000002Z",
		"pilot-1.0",
		[{"trial": "T0001", "level": "gate_run", "perturb": false, "gate": true}]
	)
	_expect(bool(first.get("ok", false)), "first synthetic session export failed")
	_expect(bool(second.get("ok", false)), "second synthetic session export failed")
	_expect(
		not FileAccess.file_exists(str(first["session_dir"]).path_join("results").path_join("gate_results.csv")),
		"empty gate table should be omitted",
	)
	_expect(
		not FileAccess.file_exists(str(second["session_dir"]).path_join("results").path_join("perturbation_results.csv")),
		"empty perturbation table should be omitted",
	)
	_expect(
		not FileAccess.file_exists(str(first["session_dir"]).path_join("qc").path_join("review_queue.csv")),
		"review package leaked into default export",
	)

	var report: Dictionary = Aggregator.new().aggregate(ROOT, OUT, false, "")
	_expect(bool(report.get("ok", false)), "aggregate of two valid sessions failed")
	var trials: Array[Dictionary] = ExperimentAnalyzer.read_csv(OUT.path_join("trials.csv"))
	var sessions: Array[Dictionary] = ExperimentAnalyzer.read_csv(OUT.path_join("sessions.csv"))
	var perturbations: Array[Dictionary] = ExperimentAnalyzer.read_csv(OUT.path_join("perturbations.csv"))
	var gates: Array[Dictionary] = ExperimentAnalyzer.read_csv(OUT.path_join("gates.csv"))
	var dyads: Array[Dictionary] = ExperimentAnalyzer.read_csv(OUT.path_join("dyads.csv"))
	_expect(sessions.size() == 2, "sessions.csv should have 2 rows")
	_expect(trials.size() == 3, "trials.csv should have 3 rows")
	_expect(perturbations.size() == 2, "perturbations.csv should have 2 rows")
	_expect(gates.size() == 1, "gates.csv should have 1 row")
	_expect(dyads.size() == 2, "dyads.csv should have 2 groups")
	_expect(not FileAccess.file_exists(OUT.path_join("segments.csv")), "empty segments table should be omitted")
	_expect(not FileAccess.file_exists(OUT.path_join("choices.csv")), "empty choices table should be omitted")
	_expect(_unique(trials, "trial_id"), "trial_id is not unique after aggregate")
	_expect(_has_identity(trials), "trials.csv missing identity columns")
	_expect(_has_identity(perturbations), "perturbations.csv missing identity columns")
	_expect(str(trials[0].get("dyad_id", "")).is_empty() == false, "joined dyad_id is empty")

	var conflict_dir: String = str(second["session_dir"]).path_join("results")
	var manifest_path: String = conflict_dir.path_join("analysis_manifest.json")
	var manifest_file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	_expect(manifest_file != null, "cannot reread manifest for version conflict")
	if manifest_file != null:
		var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
		manifest_file.close()
		if parsed is Dictionary:
			var mutated: Dictionary = parsed
			mutated["analysis_version"] = "0.0.0-conflict"
			var writer: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
			writer.store_string(JSON.stringify(mutated, "\t"))
			writer.close()
	var conflict: Dictionary = Aggregator.new().aggregate(
		ROOT, ROOT.path_join("_aggregate_conflict"), false, ""
	)
	_expect(not bool(conflict.get("ok", false)), "version conflict was silently mixed")
	_expect(
		FileAccess.file_exists(ROOT.path_join("_aggregate_conflict").path_join("aggregate_report.json")),
		"conflict report missing",
	)

	if _failures.is_empty():
		print("AGGREGATE_ASSERT_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)

func _write_session(dyad_id: String, stamp: String, condition: String, trials: Array) -> Dictionary:
	var session_dir: String = ROOT.path_join("dyad-%s" % dyad_id).path_join(stamp)
	var raw_dir: String = session_dir.path_join("raw")
	DirAccess.make_dir_recursive_absolute(raw_dir)
	var session_id: String = "%s_%s" % [dyad_id, stamp]
	var schema: Dictionary = {
		"schema_version": Aggregator.EXPECTED_SCHEMA_VERSION,
		"session": PackedStringArray([
			"schema_version", "app_version", "session_id", "dyad_id", "participant_A",
			"participant_B", "relation_condition", "protocol_version", "side_assignment",
			"started_utc", "platform", "deadzone", "curve_gamma", "force_max",
			"physics_ticks_per_second", "missing_identity_fields",
		]),
		"frames": PackedStringArray([
			"schema_version", "session_id", "monotonic_time_us", "session_elapsed_ms",
			"trial_elapsed_ms", "physics_frame", "trial_id", "life_id", "level_id",
			"level_attempt_index", "protocol_version", "physics_delta_s", "phase",
			"system_quality", "A_slot", "B_slot", "A_connected", "B_connected",
			"A_force_x", "B_force_x", "A_force_magnitude", "B_force_magnitude",
			"core_x", "core_y", "speed", "route_error_distance", "route_error_x",
			"inside_boundary", "route_max_progress",
		]),
		"events": PackedStringArray([
			"schema_version", "session_id", "monotonic_time_us", "session_elapsed_ms",
			"trial_elapsed_ms", "physics_frame", "trial_id", "life_id", "level_id",
			"level_attempt_index", "protocol_version", "event_type", "slot",
			"gain", "outcome", "component_id",
		]),
	}
	var session_row: Dictionary = {
		"schema_version": schema["schema_version"],
		"app_version": "test",
		"session_id": session_id,
		"dyad_id": dyad_id,
		"participant_A": "%s-A" % dyad_id,
		"participant_B": "%s-B" % dyad_id,
		"relation_condition": "friends",
		"protocol_version": condition,
		"side_assignment": "A=P1;B=P2",
		"started_utc": "2026-08-15T00:00:00",
		"platform": "macOS",
		"deadzone": 0.2,
		"curve_gamma": 1.6,
		"force_max": 1.0,
		"physics_ticks_per_second": 60,
		"missing_identity_fields": "",
	}
	_write_csv(raw_dir.path_join("session.csv"), schema["session"], [session_row])
	var frames: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var clock: int = 1000
	for item: Variant in trials:
		var spec: Dictionary = item
		var trial_id: String = "%s-%s" % [session_id, spec["trial"]]
		var life_id: String = "%s-L001" % trial_id
		events.append(_event_row(schema, session_id, trial_id, life_id, spec["level"], condition, clock, "trial_created"))
		clock += 10
		events.append(_event_row(schema, session_id, trial_id, life_id, spec["level"], condition, clock, "run_start"))
		clock += 10
		for i: int in 8:
			frames.append(_frame_row(
				schema, session_id, trial_id, life_id, spec["level"], condition, clock, i * 20.0
			))
			clock += 10
		if bool(spec.get("perturb", false)):
			var on: Dictionary = _event_row(
				schema, session_id, trial_id, life_id, spec["level"], condition, clock, "perturb_on"
			)
			on["slot"] = 0
			on["gain"] = 0.5
			events.append(on)
			clock += 10
			var off: Dictionary = _event_row(
				schema, session_id, trial_id, life_id, spec["level"], condition, clock, "perturb_off"
			)
			off["slot"] = 0
			off["gain"] = 1.0
			events.append(off)
			clock += 10
		if bool(spec.get("gate", false)):
			var attempt: Dictionary = _event_row(
				schema, session_id, trial_id, life_id, spec["level"], condition, clock, "gate_attempt"
			)
			attempt["component_id"] = "gate_1"
			events.append(attempt)
			clock += 10
			var opened: Dictionary = _event_row(
				schema, session_id, trial_id, life_id, spec["level"], condition, clock, "gate_opened"
			)
			opened["component_id"] = "gate_1"
			events.append(opened)
			clock += 10
		var end_event: Dictionary = _event_row(
			schema, session_id, trial_id, life_id, spec["level"], condition, clock, "trial_end"
		)
		end_event["outcome"] = "success"
		events.append(end_event)
		clock += 10
	_write_csv(raw_dir.path_join("frames.csv"), schema["frames"], frames)
	_write_csv(raw_dir.path_join("events.csv"), schema["events"], events)
	var paths: Dictionary = Aggregator.resolve_session_paths(session_dir)
	return {
		"ok": ExperimentAnalyzer.export_session(paths),
		"session_dir": session_dir,
		"session_id": session_id,
	}

func _event_row(
	schema: Dictionary,
	session_id: String,
	trial_id: String,
	life_id: String,
	level_id: String,
	condition: String,
	clock: int,
	event_type: String,
) -> Dictionary:
	var row: Dictionary = {}
	for column: String in schema["events"]:
		row[column] = ""
	row["schema_version"] = schema["schema_version"]
	row["session_id"] = session_id
	row["monotonic_time_us"] = clock
	row["session_elapsed_ms"] = clock / 1000
	row["trial_elapsed_ms"] = 200
	row["physics_frame"] = 1
	row["trial_id"] = trial_id
	row["life_id"] = life_id
	row["level_id"] = level_id
	row["level_attempt_index"] = 1
	row["protocol_version"] = condition
	row["event_type"] = event_type
	return row

func _frame_row(
	schema: Dictionary,
	session_id: String,
	trial_id: String,
	life_id: String,
	level_id: String,
	condition: String,
	clock: int,
	time_ms: float,
) -> Dictionary:
	var row: Dictionary = {}
	for column: String in schema["frames"]:
		row[column] = ""
	row["schema_version"] = schema["schema_version"]
	row["session_id"] = session_id
	row["monotonic_time_us"] = clock
	row["session_elapsed_ms"] = clock / 1000
	row["trial_elapsed_ms"] = time_ms
	row["physics_frame"] = int(time_ms)
	row["trial_id"] = trial_id
	row["life_id"] = life_id
	row["level_id"] = level_id
	row["level_attempt_index"] = 1
	row["protocol_version"] = condition
	row["physics_delta_s"] = 0.02
	row["phase"] = "running"
	row["system_quality"] = "ok"
	row["A_slot"] = 0
	row["B_slot"] = 1
	row["A_connected"] = 1
	row["B_connected"] = 1
	row["A_force_x"] = 0.4
	row["B_force_x"] = 0.4
	row["A_force_magnitude"] = 0.4
	row["B_force_magnitude"] = 0.4
	row["core_x"] = time_ms * 0.01
	row["core_y"] = 0
	row["speed"] = 8
	row["route_error_distance"] = 2
	row["route_error_x"] = 2
	row["inside_boundary"] = 1
	row["route_max_progress"] = 0.2
	return row

func _write_csv(path: String, columns: PackedStringArray, rows: Array) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var header: Array[Variant] = []
	for column: String in columns:
		header.append(column)
	file.store_string(_csv_row(header) + "\r\n")
	for item: Variant in rows:
		var row: Dictionary = item
		var values: Array[Variant] = []
		for column: String in columns:
			values.append(row.get(column, ""))
		file.store_string(_csv_row(values) + "\r\n")
	file.close()

func _reset_root() -> void:
	if DirAccess.dir_exists_absolute(ROOT):
		_remove_recursive(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	for filename: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(child))
	DirAccess.remove_absolute(path)

func _unique(rows: Array[Dictionary], field: String) -> bool:
	var seen: Dictionary = {}
	for row: Dictionary in rows:
		var key: String = str(row.get(field, ""))
		if key.is_empty() or seen.has(key):
			return false
		seen[key] = true
	return true

func _has_identity(rows: Array[Dictionary]) -> bool:
	if rows.is_empty():
		return false
	for field: String in Aggregator.IDENTITY_COLUMNS:
		if not rows[0].has(field):
			return false
	return true

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

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
