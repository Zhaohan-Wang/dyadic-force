class_name ExperimentAggregator
extends RefCounted
## 跨 session 汇总：补齐身份列、校验版本/主键，并按需写出专项总表。

const EXPECTED_SCHEMA_VERSION: String = "3.1.0"
const RAW_FOLDER: String = "raw"
const RESULTS_FOLDER: String = "results"
const QC_FOLDER: String = "qc"

const IDENTITY_COLUMNS: PackedStringArray = [
	"dyad_id", "participant_A", "participant_B", "relation_condition",
	"side_assignment", "started_utc", "session_dir",
]

const SESSION_INDEX_EXTRA: PackedStringArray = [
	"session_dir", "results_dir", "trial_count", "raw_complete",
	"analysis_version", "reanalysis_ok", "missing_trial_end_count",
]

const SESSION_REQUIRED: PackedStringArray = [
	"schema_version", "session_id", "dyad_id", "participant_A", "participant_B",
	"relation_condition", "protocol_version", "started_utc",
]

const STUDY_DYAD_COLUMNS: PackedStringArray = [
	"analysis_version", "dyad_id", "protocol_version", "level_id",
	"session_count", "trial_count", "success_count", "success_rate",
	"restarted_count", "quit_count", "A_leader_count", "B_leader_count",
	"ambiguous_count", "same_leader_stability", "mean_completion_time_ms",
	"mean_route_error", "mean_max_progress",
]

static func _result_specs() -> Array[Dictionary]:
	return [
		{
			"key": "trials",
			"filename": "trial_results.csv",
			"out": "trials.csv",
			"columns": ExperimentAnalyzer.TRIAL_COLUMNS,
			"id_fields": PackedStringArray(["trial_id"]),
		},
		{
			"key": "perturbations",
			"filename": "perturbation_results.csv",
			"out": "perturbations.csv",
			"columns": ExperimentAnalyzer.PERTURBATION_COLUMNS,
			"id_fields": PackedStringArray(["perturbation_id"]),
		},
		{
			"key": "gates",
			"filename": "gate_results.csv",
			"out": "gates.csv",
			"columns": ExperimentAnalyzer.GATE_COLUMNS,
			"id_fields": PackedStringArray(["session_id", "trial_id", "gate_id"]),
		},
		{
			"key": "segments",
			"filename": "segment_results.csv",
			"out": "segments.csv",
			"columns": ExperimentAnalyzer.SEGMENT_COLUMNS,
			"id_fields": PackedStringArray(["session_id", "trial_id", "segment_id", "enter_ms"]),
		},
		{
			"key": "choices",
			"filename": "choice_results.csv",
			"out": "choices.csv",
			"columns": ExperimentAnalyzer.CHOICE_COLUMNS,
			"id_fields": PackedStringArray(["session_id", "trial_id", "fork_id"]),
		},
	]

func aggregate(
	root_path: String,
	out_path: String,
	reanalyze_missing: bool = false,
	dyad_filter: String = "",
) -> Dictionary:
	var report: Dictionary = {
		"root": root_path,
		"out": out_path,
		"included": [],
		"skipped": [],
		"errors": [],
		"counts": {},
		"schema_version": "",
		"analysis_version": "",
	}
	if root_path.is_empty() or out_path.is_empty():
		report["errors"].append("root and out paths are required")
		return _fail(report)
	var sessions: Array[Dictionary] = []
	for session_dir: String in session_directories_under(root_path):
		var inspected: Dictionary = _inspect_session(session_dir, reanalyze_missing, dyad_filter)
		if str(inspected.get("status", "")) == "included":
			sessions.append(inspected)
			report["included"].append(_session_brief(inspected))
		elif str(inspected.get("status", "")) == "skipped":
			report["skipped"].append(_session_brief(inspected))
		else:
			report["errors"].append(_session_brief(inspected))
	if sessions.is_empty():
		report["errors"].append("no sessions included")
		_write_report(out_path, report)
		return _fail(report)
	var schema_version: String = str(sessions[0].get("schema_version", ""))
	var analysis_version: String = str(sessions[0].get("analysis_version", ""))
	for session: Dictionary in sessions:
		if str(session.get("schema_version", "")) != schema_version:
			report["errors"].append({
				"session_id": session.get("session_id", ""),
				"reason": "schema_version mismatch: %s vs %s" % [
					session.get("schema_version", ""), schema_version,
				],
			})
		if str(session.get("analysis_version", "")) != analysis_version:
			report["errors"].append({
				"session_id": session.get("session_id", ""),
				"reason": "analysis_version mismatch: %s vs %s" % [
					session.get("analysis_version", ""), analysis_version,
				],
			})
	if not (report["errors"] as Array).is_empty():
		_write_report(out_path, report)
		return _fail(report)
	if DirAccess.make_dir_recursive_absolute(out_path) != OK and not DirAccess.dir_exists_absolute(out_path):
		report["errors"].append("cannot create output directory")
		return _fail(report)
	report["schema_version"] = schema_version
	report["analysis_version"] = analysis_version
	var session_rows: Array[Dictionary] = []
	for session: Dictionary in sessions:
		session_rows.append(session["index_row"])
	var session_columns: PackedStringArray = _header_of(
		str((sessions[0]["paths"] as Dictionary).get("session", ""))
	)
	if session_columns.is_empty():
		report["errors"].append("cannot read session.csv header")
		_write_report(out_path, report)
		return _fail(report)
	session_columns.append_array(SESSION_INDEX_EXTRA)
	if not _write_csv(out_path.path_join("sessions.csv"), session_columns, session_rows):
		report["errors"].append("failed to write sessions.csv")
		_write_report(out_path, report)
		return _fail(report)
	report["counts"]["sessions"] = session_rows.size()
	var all_trials: Array[Dictionary] = []
	for spec: Dictionary in _result_specs():
		var combined: Array[Dictionary] = []
		var seen: Dictionary = {}
		for session: Dictionary in sessions:
			for row: Dictionary in session[spec["key"]]:
				var key: String = _row_key(row, spec["id_fields"])
				if seen.has(key):
					report["errors"].append({
						"session_id": session.get("session_id", ""),
						"reason": "duplicate %s key %s" % [spec["out"], key],
					})
					continue
				seen[key] = true
				combined.append(row)
		if spec["key"] == "trials":
			all_trials = combined
		if combined.is_empty():
			_remove_if_exists(out_path.path_join(str(spec["out"])))
			report["counts"][spec["key"]] = 0
			continue
		var columns: PackedStringArray = IDENTITY_COLUMNS.duplicate()
		for column: String in spec["columns"]:
			if not columns.has(column):
				columns.append(column)
		if not _write_csv(out_path.path_join(str(spec["out"])), columns, combined):
			report["errors"].append("failed to write %s" % spec["out"])
			_write_report(out_path, report)
			return _fail(report)
		report["counts"][spec["key"]] = combined.size()
	if not (report["errors"] as Array).is_empty():
		_write_report(out_path, report)
		return _fail(report)
	var dyad_rows: Array[Dictionary] = _study_dyads(all_trials)
	if dyad_rows.is_empty():
		_remove_if_exists(out_path.path_join("dyads.csv"))
		report["counts"]["dyads"] = 0
	elif not _write_csv(out_path.path_join("dyads.csv"), STUDY_DYAD_COLUMNS, dyad_rows):
		report["errors"].append("failed to write dyads.csv")
		_write_report(out_path, report)
		return _fail(report)
	else:
		report["counts"]["dyads"] = dyad_rows.size()
	report["ok"] = true
	_write_report(out_path, report)
	return report

func _inspect_session(session_dir: String, reanalyze_missing: bool, dyad_filter: String) -> Dictionary:
	var paths: Dictionary = resolve_session_paths(session_dir)
	var result: Dictionary = {
		"status": "error",
		"session_dir": session_dir,
		"session_id": "",
		"reason": "",
	}
	var raw_complete: bool = (
		FileAccess.file_exists(str(paths["session"]))
		and FileAccess.file_exists(str(paths["frames"]))
		and FileAccess.file_exists(str(paths["events"]))
	)
	if not raw_complete:
		result["reason"] = "raw CSV missing"
		return result
	var session_rows: Array[Dictionary] = ExperimentAnalyzer.read_csv(str(paths["session"]))
	if session_rows.is_empty():
		result["reason"] = "session.csv unreadable"
		return result
	var session: Dictionary = session_rows[0]
	var session_id: String = str(session.get("session_id", ""))
	var dyad_id: String = str(session.get("dyad_id", ""))
	result["session_id"] = session_id
	if not dyad_filter.is_empty() and dyad_id != dyad_filter and not session_dir.contains("dyad-%s" % dyad_filter):
		result["status"] = "skipped"
		result["reason"] = "dyad filter"
		return result
	if not _header_has(str(paths["session"]), SESSION_REQUIRED):
		result["reason"] = "session.csv missing required identity columns"
		return result
	var events: Array[Dictionary] = ExperimentAnalyzer.read_csv(str(paths["events"]))
	var missing_trial_end: int = _missing_trial_end_count(events)
	var reanalysis_ok: bool = FileAccess.file_exists(str(paths["analysis_manifest"]))
	if (not reanalysis_ok or not FileAccess.file_exists(str(paths["trial_results"]))) and reanalyze_missing:
		reanalysis_ok = ExperimentAnalyzer.export_session(paths)
	if not FileAccess.file_exists(str(paths["trial_results"])) or not FileAccess.file_exists(str(paths["analysis_manifest"])):
		result["reason"] = "results missing"
		return result
	var manifest: Dictionary = _read_json(str(paths["analysis_manifest"]))
	var analysis_version: String = str(manifest.get("analysis_version", ""))
	if analysis_version != ExperimentProtocol.ANALYSIS_VERSION:
		result["reason"] = "analysis_version %s != %s" % [
			analysis_version, ExperimentProtocol.ANALYSIS_VERSION,
		]
		return result
	if str(session.get("schema_version", "")) != EXPECTED_SCHEMA_VERSION:
		result["reason"] = "schema_version %s != %s" % [
			session.get("schema_version", ""), EXPECTED_SCHEMA_VERSION,
		]
		return result
	var identity: Dictionary = {
		"dyad_id": dyad_id,
		"participant_A": session.get("participant_A", ""),
		"participant_B": session.get("participant_B", ""),
		"relation_condition": session.get("relation_condition", ""),
		"side_assignment": session.get("side_assignment", ""),
		"started_utc": session.get("started_utc", ""),
		"session_dir": session_dir,
	}
	var loaded: Dictionary = {}
	for spec: Dictionary in _result_specs():
		var rows: Array[Dictionary] = []
		var path: String = str(paths["results_directory"]).path_join(str(spec["filename"]))
		if FileAccess.file_exists(path):
			if not _header_matches(path, spec["columns"]):
				result["reason"] = "%s header mismatch" % spec["filename"]
				return result
			for row: Dictionary in ExperimentAnalyzer.read_csv(path):
				var enriched: Dictionary = identity.duplicate()
				enriched.merge(row, true)
				rows.append(enriched)
		loaded[spec["key"]] = rows
	var index_row: Dictionary = session.duplicate()
	index_row["session_dir"] = session_dir
	index_row["results_dir"] = paths["results_directory"]
	index_row["trial_count"] = (loaded["trials"] as Array).size()
	index_row["raw_complete"] = 1
	index_row["analysis_version"] = analysis_version
	index_row["reanalysis_ok"] = 1 if reanalysis_ok else 0
	index_row["missing_trial_end_count"] = missing_trial_end
	result["status"] = "included"
	result["schema_version"] = session.get("schema_version", "")
	result["analysis_version"] = analysis_version
	result["index_row"] = index_row
	result["paths"] = paths
	for key: Variant in loaded:
		result[key] = loaded[key]
	return result

func _study_dyads(trials: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for trial: Dictionary in trials:
		var key: String = "%s|%s|%s" % [
			trial.get("dyad_id", ""),
			trial.get("protocol_version", ""),
			trial.get("level_id", ""),
		]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(trial)
	var output: Array[Dictionary] = []
	for key: Variant in groups.keys():
		var selected: Array = groups[key]
		var success_count: int = 0
		var restarted_count: int = 0
		var quit_count: int = 0
		var a_count: int = 0
		var b_count: int = 0
		var ambiguous_count: int = 0
		var sessions: Dictionary = {}
		var completion_times: Array[float] = []
		var errors: Array[float] = []
		var progresses: Array[float] = []
		for item: Variant in selected:
			var trial: Dictionary = item as Dictionary
			sessions[str(trial.get("session_id", ""))] = true
			var outcome: String = str(trial.get("outcome", ""))
			if outcome == "success":
				success_count += 1
			elif outcome == "restarted":
				restarted_count += 1
			elif outcome == "quit":
				quit_count += 1
			var leader: String = str(trial.get("trial_leader", "ambiguous"))
			if leader == "A":
				a_count += 1
			elif leader == "B":
				b_count += 1
			else:
				ambiguous_count += 1
			_append_number(completion_times, trial.get("completion_time_ms"))
			_append_number(errors, trial.get("mean_route_error"))
			_append_number(progresses, trial.get("max_progress"))
		var count: int = selected.size()
		var decisive: int = a_count + b_count
		var first: Dictionary = selected[0] as Dictionary
		output.append({
			"analysis_version": ExperimentProtocol.ANALYSIS_VERSION,
			"dyad_id": first.get("dyad_id", ""),
			"protocol_version": first.get("protocol_version", ""),
			"level_id": first.get("level_id", ""),
			"session_count": sessions.size(),
			"trial_count": count,
			"success_count": success_count,
			"success_rate": float(success_count) / count if count > 0 else null,
			"restarted_count": restarted_count,
			"quit_count": quit_count,
			"A_leader_count": a_count,
			"B_leader_count": b_count,
			"ambiguous_count": ambiguous_count,
			"same_leader_stability": float(maxi(a_count, b_count)) / decisive if decisive > 0 else null,
			"mean_completion_time_ms": _mean(completion_times),
			"mean_route_error": _mean(errors),
			"mean_max_progress": _mean(progresses),
		})
	return output

static func session_directories_under(root_path: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(root_path):
		return result
	for child: String in DirAccess.get_directories_at(root_path):
		if child.begins_with("_"):
			continue
		var child_path: String = root_path.path_join(child)
		if _looks_like_session_dir(child_path):
			result.append(child_path)
			continue
		for grandchild: String in DirAccess.get_directories_at(child_path):
			if grandchild.begins_with("_"):
				continue
			var session_path: String = child_path.path_join(grandchild)
			if _looks_like_session_dir(session_path):
				result.append(session_path)
	return result

static func resolve_session_paths(session_dir: String) -> Dictionary:
	var raw_dir: String = session_dir.path_join(RAW_FOLDER)
	var results_dir: String = session_dir.path_join(RESULTS_FOLDER)
	var qc_dir: String = session_dir.path_join(QC_FOLDER)
	return {
		"directory": session_dir,
		"raw_directory": raw_dir,
		"results_directory": results_dir,
		"qc_directory": qc_dir,
		"session": raw_dir.path_join("session.csv"),
		"frames": raw_dir.path_join("frames.csv"),
		"events": raw_dir.path_join("events.csv"),
		"analysis_manifest": results_dir.path_join("analysis_manifest.json"),
		"trial_results": results_dir.path_join("trial_results.csv"),
		"perturbation_results": results_dir.path_join("perturbation_results.csv"),
		"gate_results": results_dir.path_join("gate_results.csv"),
		"segment_results": results_dir.path_join("segment_results.csv"),
		"choice_results": results_dir.path_join("choice_results.csv"),
		"review_queue": qc_dir.path_join("review_queue.csv"),
	}

static func _looks_like_session_dir(path: String) -> bool:
	return FileAccess.file_exists(path.path_join(RAW_FOLDER).path_join("events.csv"))

func _header_of(path: String) -> PackedStringArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var header: PackedStringArray = file.get_csv_line()
	file.close()
	return header

func _header_has(path: String, required: PackedStringArray) -> bool:
	var header: PackedStringArray = _header_of(path)
	for field: String in required:
		if not header.has(field):
			return false
	return true

func _header_matches(path: String, expected: PackedStringArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var header: PackedStringArray = file.get_csv_line()
	file.close()
	if header.size() != expected.size():
		return false
	for i: int in expected.size():
		if header[i] != expected[i]:
			return false
	return true

func _missing_trial_end_count(events: Array[Dictionary]) -> int:
	var created: Dictionary = {}
	var ended: Dictionary = {}
	for event: Dictionary in events:
		var trial_id: String = str(event.get("trial_id", ""))
		if trial_id.is_empty():
			continue
		if str(event.get("event_type", "")) == "trial_created":
			created[trial_id] = true
		elif str(event.get("event_type", "")) == "trial_end":
			ended[trial_id] = true
	var missing: int = 0
	for trial_id: Variant in created.keys():
		if not ended.has(trial_id):
			missing += 1
	return missing

func _row_key(row: Dictionary, fields: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for field: String in fields:
		parts.append(str(row.get(field, "")))
	return "|".join(parts)

func _session_brief(session: Dictionary) -> Dictionary:
	return {
		"session_id": session.get("session_id", ""),
		"session_dir": session.get("session_dir", ""),
		"reason": session.get("reason", ""),
	}

func _fail(report: Dictionary) -> Dictionary:
	report["ok"] = false
	return report

func _write_report(out_path: String, report: Dictionary) -> void:
	if out_path.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(out_path) != OK and not DirAccess.dir_exists_absolute(out_path):
		return
	var file: FileAccess = FileAccess.open(out_path.path_join("aggregate_report.json"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}

func _write_csv(path: String, columns: PackedStringArray, rows: Array[Dictionary]) -> bool:
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

func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _append_number(output: Array[float], value: Variant) -> void:
	if value == null or str(value).is_empty():
		return
	var text: String = str(value)
	if text.is_valid_float():
		output.append(text.to_float())

func _mean(values: Array[float]) -> Variant:
	if values.is_empty():
		return null
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / values.size()

func _csv_row(values: Array[Variant]) -> String:
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
