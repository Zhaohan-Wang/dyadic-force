extends SceneTree
## 聚焦验证：路线投影、RFC4180、唯一 session 与不可覆盖 trial/life。

var _failures: PackedStringArray = PackedStringArray()
var _log: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_log = root.get_node_or_null("ExperimentLog")
	if _log == null:
		push_error("ExperimentLog autoload is unavailable")
		quit(1)
		return
	_test_route_tracker()
	_test_csv_codec()
	_test_level_routes()
	_test_session_lifecycle()
	if _failures.is_empty():
		print("EXPERIMENT_PIPELINE_ASSERT_OK")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _test_route_tracker() -> void:
	var line: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100),
	])
	var result: Dictionary = RouteTracker.project_point(Vector2(25, 12), line, 20.0)
	_expect(int(result["segment"]) == 0, "route segment mismatch")
	_expect(is_equal_approx(float(result["signed_error"]), 12.0), "signed error mismatch")
	_expect(is_equal_approx(float(result["progress"]), 0.125), "route progress mismatch")
	_expect(bool(result["inside_boundary"]), "inside boundary mismatch")
	var outside: Dictionary = RouteTracker.project_point(Vector2(25, 30), line, 20.0)
	_expect(not bool(outside["inside_boundary"]), "outside boundary mismatch")

func _test_csv_codec() -> void:
	var log_script: Script = _log.get_script() as Script
	var row: String = str(log_script.call("csv_row", [
		"plain", "comma,value", "quote\"value", "line\nvalue", "", true,
	]))
	var parsed: PackedStringArray = row.split(",", true)
	# split 仅用于确认编码确实加引号；完整标准解析在 session 文件测试中执行。
	_expect(parsed.size() > 6, "CSV test fixture did not contain delimiters")
	_expect(row.contains("\"comma,value\""), "comma was not RFC4180 escaped")
	_expect(row.contains("\"quote\"\"value\""), "quote was not RFC4180 escaped")
	_expect(row.contains("\"line\nvalue\""), "newline was not RFC4180 escaped")

func _test_level_routes() -> void:
	for path: String in GameState.LEVEL_ORDER:
		var level_def: LevelDef = load(path) as LevelDef
		_expect(level_def != null, "cannot load %s" % path)
		if level_def == null:
			continue
		_expect(level_def.route_centerline.size() >= 2, "%s route missing" % path)
		_expect(
			level_def.route_centerline[0].distance_to(level_def.spawn_point) < 1.0,
			"%s route does not start at spawn" % path,
		)
		_expect(
			level_def.route_centerline[-1].distance_to(level_def.goal_point) < 1.0,
			"%s route does not end at goal" % path,
		)
		_expect(level_def.route_corridor_half_width > 0.0, "%s corridor width invalid" % path)

func _test_session_lifecycle() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state != null:
		game_state.set("experiment_mode", true)
		game_state.set("dyad_id", "S1-D009")
		game_state.set("participant_A", "S1-D009-A")
		game_state.set("participant_B", "S1-D009-B")
		game_state.set("relation_condition", "friends")
		game_state.set("protocol_version", "pilot-1.0")
		game_state.set("experiment_setup_locked", true)
	var level_def: LevelDef = load("res://levels/practice.tres") as LevelDef
	_expect(bool(_log.call("begin_trial", level_def, "baseline")), "first trial failed")
	var first: Dictionary = _log.call("summary_dict") as Dictionary
	_log.call("log_event", "test_event", {"note": "comma,\"quote\"\nline"})
	_log.call("begin_life", "test")
	var first_life: String = str((_log.call("summary_dict") as Dictionary)["life_id"])
	_log.call("end_trial", "restarted")
	_expect(bool(_log.call("begin_trial", level_def, "baseline")), "second trial failed")
	var second: Dictionary = _log.call("summary_dict") as Dictionary
	_expect(first["session_id"] == second["session_id"], "trial changed session id")
	_expect(first["trial_id"] != second["trial_id"], "trial id was reused")
	_expect(str(first["life_id"]) != first_life, "life id did not increment")
	_expect(first["log_events"] == second["log_events"], "trials did not share session events")
	_expect(
		str(second["data_directory"]).contains("experiments")
		and str(second["data_directory"]).contains("dyad-"),
		"session directory is not under experiments/dyad-*",
	)
	_expect(
		str(second["log_events"]).contains("/raw/events.csv"),
		"raw events.csv was not stored in the raw/ folder",
	)
	_log.call("end_trial", "success")
	_log.call("flush")
	var events: FileAccess = FileAccess.open(str(second["log_events"]), FileAccess.READ)
	_expect(events != null, "events.csv missing")
	if events != null:
		var header: PackedStringArray = events.get_csv_line()
		var schema: Dictionary = _log.call("schema_columns") as Dictionary
		_expect(
			header.size() == (schema["events"] as PackedStringArray).size(),
			"events.csv header column count mismatch",
		)
		var saw_trial_end: bool = false
		while events.get_position() < events.get_length():
			var values: PackedStringArray = events.get_csv_line()
			if values.size() == header.size() and values[11] == "trial_end":
				saw_trial_end = true
		_expect(saw_trial_end, "events.csv missing trial_end")
		events.close()
	_log.call("close_session")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
