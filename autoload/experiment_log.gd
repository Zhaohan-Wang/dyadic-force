extends Node
## 唯一实验会话日志。每次应用运行只创建一个 session 目录，所有 trial/life 追加写入。
## 导出游戏可写目录：user://experiments/station-<采集站>/dyad-<组号>/<UTC时间>/raw|results|qc/

const ROOT_DIR: String = "user://experiments"
const RAW_FOLDER: String = "raw"
const RESULTS_FOLDER: String = "results"
const QC_FOLDER: String = "qc"
const SCHEMA_VERSION: String = "3.2.0"
const FLUSH_INTERVAL_S: float = 1.0
const FULL_PUSH_THRESHOLD: float = 0.90
const FINE_MIN: float = 0.20
const FINE_MAX: float = 0.75

const SESSION_COLUMNS: PackedStringArray = [
	"schema_version", "app_version", "session_id", "station_id", "dyad_id",
	"participant_A", "participant_B", "relation_condition", "protocol_version",
	"side_assignment", "started_utc", "platform", "deadzone", "curve_gamma",
	"force_max", "physics_ticks_per_second", "missing_identity_fields",
]
const CLOCK_COLUMNS: PackedStringArray = [
	"schema_version", "session_id", "monotonic_time_us", "session_elapsed_ms",
	"trial_elapsed_ms", "physics_frame", "trial_id", "life_id", "level_id",
	"level_attempt_index", "protocol_version",
]
const FRAME_COLUMNS: PackedStringArray = [
	"schema_version", "session_id", "monotonic_time_us", "session_elapsed_ms",
	"trial_elapsed_ms", "physics_frame", "trial_id", "life_id", "level_id",
	"level_attempt_index", "protocol_version",
	"physics_delta_s", "render_fps", "phase", "system_quality",
	"A_slot", "A_source", "A_device_id", "A_connected",
	"A_raw_x", "A_raw_y", "A_calibrated_x", "A_calibrated_y",
	"A_deadzone_magnitude", "A_curve_magnitude", "A_gain",
	"A_force_x", "A_force_y", "A_force_magnitude",
	"B_slot", "B_source", "B_device_id", "B_connected",
	"B_raw_x", "B_raw_y", "B_calibrated_x", "B_calibrated_y",
	"B_deadzone_magnitude", "B_curve_magnitude", "B_gain",
	"B_force_x", "B_force_y", "B_force_magnitude",
	"core_x", "core_y", "velocity_x", "velocity_y", "speed",
	"angle_rad", "angular_velocity_rad_s",
	"route_error_x", "route_error_y", "route_signed_error",
	"route_error_distance", "route_progress", "route_max_progress",
	"route_segment", "inside_boundary", "completion_dir_x", "completion_dir_y",
	"task_segment_id", "task_segment_type", "active_gate_id",
	"active_choice_id", "current_branch",
]
const EVENT_COLUMNS: PackedStringArray = [
	"schema_version", "session_id", "monotonic_time_us", "session_elapsed_ms",
	"trial_elapsed_ms", "physics_frame", "trial_id", "life_id", "level_id",
	"level_attempt_index", "protocol_version",
	"event_type", "phase", "slot", "device_id", "gain", "impact_strength",
	"damage", "remaining_hp", "time_penalty_s", "core_x", "core_y",
	"outcome", "note",
	"component_id", "segment_id", "collision_category", "result_reason",
	"branch", "sequence_version",
]

var _session_id: String = ""
var _session_dir: String = ""
var _paths: Dictionary = {}
var _session_start_us: int = 0
var _last_clock_us: int = 0
var _trial_start_us: int = 0
var _trial_serial: int = 0
var _life_serial: int = 0
var _trial_id: String = ""
var _life_id: String = ""
var _level_id: String = ""
var _protocol_version: String = ""
var _level_attempt_index: int = 0
var _attempts_by_level: Dictionary = {}
var _known_device_slots: Dictionary = {}
var _trial_active: bool = false
var _last_physics_frame: int = -1
var _completion_direction: Vector2 = Vector2.RIGHT
var _route_tracker: RouteTracker = RouteTracker.new()
## 当前任务路段 / 门 / 岔路上下文（由 Level 每帧刷新）
var _task_segment_id: String = ""
var _task_segment_type: String = ""
var _active_gate_id: String = ""
var _active_choice_id: String = ""
var _current_branch: String = ""

var _frames_file: FileAccess = null
var _events_file: FileAccess = null
var _frames_buffer: PackedStringArray = PackedStringArray()
var _events_buffer: PackedStringArray = PackedStringArray()
var _flush_left: float = FLUSH_INTERVAL_S
var _last_export_ok: bool = false
var _last_export_message: String = "not_run"
var _last_export_finished_us: int = 0

var total_force_sum: float = 0.0
var sample_count: int = 0
var full_push_count: int = 0
var fine_control_count: int = 0
var active_input_count: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_recover_interrupted_sessions(ROOT_DIR)
	if not InputHub.joy_hotplug.is_connected(_on_joy_hotplug):
		InputHub.joy_hotplug.connect(_on_joy_hotplug)

func _process(delta: float) -> void:
	if _session_id.is_empty():
		return
	_flush_left -= delta
	if _flush_left <= 0.0:
		_flush_left = FLUSH_INTERVAL_S
		flush()

## 每次进入/重开关卡建立不可覆盖的 trial；session 在首次调用时惰性创建。
## 非实验模式下不落盘，仍返回 true，避免关卡被日志失败卡住。
func begin_trial(level_def: LevelDef, _unused_condition: String = "") -> bool:
	if level_def == null:
		push_error("ExperimentLog: begin_trial requires LevelDef")
		return false
	if not bool(GameState.get("experiment_mode")):
		if _trial_active:
			end_trial("aborted", "experiment_mode_disabled")
		_trial_active = false
		_last_export_ok = false
		_last_export_message = "disabled"
		_session_id = ""
		_session_dir = ""
		_paths = {}
		_trial_id = ""
		_life_id = ""
		_level_id = level_def.level_id
		_protocol_version = _active_protocol_version()
		return true
	if _trial_active:
		end_trial("aborted", "implicit_trial_replacement")
	if not _ensure_session():
		return false
	_trial_serial += 1
	_life_serial = 1
	_level_id = level_def.level_id
	_protocol_version = _active_protocol_version()
	_level_attempt_index = int(_attempts_by_level.get(_level_id, 0)) + 1
	_attempts_by_level[_level_id] = _level_attempt_index
	_trial_id = "%s-T%04d" % [_session_id, _trial_serial]
	_life_id = "%s-L%03d" % [_trial_id, _life_serial]
	_trial_start_us = _clock_us()
	_last_physics_frame = -1
	_completion_direction = level_def.route_completion_direction.normalized()
	_route_tracker.configure(level_def.route_centerline, level_def.route_corridor_half_width)
	_reset_trial_summary()
	_trial_active = true
	log_event("trial_created", {
		"note": "corridor_half_width=%.3f" % level_def.route_corridor_half_width,
	})
	return true

## 旧调用兼容：优先使用当前 LevelDef，但不再把 trial 当作 session。
func begin_session(_level_id_compat: String, condition: String) -> void:
	var level_def: LevelDef = GameState.current_level as LevelDef
	if level_def != null:
		begin_trial(level_def, condition)

func begin_life(note: String = "") -> void:
	if not _trial_active:
		return
	_life_serial += 1
	_life_id = "%s-L%03d" % [_trial_id, _life_serial]
	_route_tracker.reset_life()
	log_event("respawn_end", {"note": note})

func end_trial(outcome: String, note: String = "") -> bool:
	if not _trial_active:
		return _last_export_ok
	log_event("trial_end", {"outcome": outcome, "note": note})
	_trial_active = false
	flush()
	_last_export_ok = ExperimentAnalyzer.export_session(output_paths())
	_last_export_finished_us = _clock_us()
	_last_export_message = "saved" if _last_export_ok else "analysis_failed"
	if not _last_export_ok:
		push_warning("ExperimentLog: derived analysis export failed")
	return _last_export_ok

## 由关卡每帧刷新任务上下文，写入 frames.csv 扩展列。
func set_task_context(
	segment_id: String,
	segment_type: String,
	gate_id: String,
	choice_id: String,
	branch: String,
) -> void:
	_task_segment_id = segment_id
	_task_segment_type = segment_type
	_active_gate_id = gate_id
	_active_choice_id = choice_id
	_current_branch = branch

## 每个物理帧严格一行 A/B 宽表，事件与帧共享同一时钟生成器。
func log_frame(physics_delta: float, phase: String, ball: RigidBody2D) -> void:
	if not _trial_active or ball == null:
		return
	var physics_frame: int = Engine.get_physics_frames()
	if physics_frame == _last_physics_frame:
		return
	_last_physics_frame = physics_frame
	var clock: Dictionary = _clock_snapshot(physics_frame)
	var route: Dictionary = _route_tracker.sample(ball.global_position)
	var a_slot: int = _participant_slot("A")
	var b_slot: int = 1 - a_slot
	var a: Dictionary = _slot_snapshot(a_slot)
	var b: Dictionary = _slot_snapshot(b_slot)
	_accumulate_sample(a["sample"] as ForceMapper.Sample)
	_accumulate_sample(b["sample"] as ForceMapper.Sample)
	var quality: String = "ok"
	var nominal_delta: float = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	if physics_delta > nominal_delta * 1.5:
		quality = "late"
	if not bool(a["connected"]) or not bool(b["connected"]):
		quality = "disconnected"
	var row: Array[Variant] = _clock_values(clock)
	row.append_array([
		physics_delta, Engine.get_frames_per_second(), phase, quality,
		a_slot, a["source"], a["device_id"], a["connected"],
		a["raw_x"], a["raw_y"], a["cal_x"], a["cal_y"],
		a["m1"], a["m2"], a["gain"], a["fx"], a["fy"], a["f_mag"],
		b_slot, b["source"], b["device_id"], b["connected"],
		b["raw_x"], b["raw_y"], b["cal_x"], b["cal_y"],
		b["m1"], b["m2"], b["gain"], b["fx"], b["fy"], b["f_mag"],
		ball.global_position.x, ball.global_position.y,
		ball.linear_velocity.x, ball.linear_velocity.y, ball.linear_velocity.length(),
		ball.rotation, ball.angular_velocity,
		(route["error"] as Vector2).x, (route["error"] as Vector2).y,
		route["signed_error"], route["distance"], route["progress"],
		route["max_progress"], route["segment"], route["inside_boundary"],
		_completion_direction.x, _completion_direction.y,
		_task_segment_id, _task_segment_type, _active_gate_id,
		_active_choice_id, _current_branch,
	])
	_frames_buffer.append(csv_row(row))

func log_event(event_type: String, data: Dictionary = {}) -> void:
	if not _trial_active or _events_file == null:
		return
	var clock: Dictionary = _clock_snapshot(Engine.get_physics_frames())
	var row: Array[Variant] = _clock_values(clock)
	row.append_array([
		event_type,
		data.get("phase", ""),
		data.get("slot", ""),
		data.get("device_id", ""),
		data.get("gain", ""),
		data.get("impact_strength", ""),
		data.get("damage", ""),
		data.get("remaining_hp", ""),
		data.get("time_penalty_s", ""),
		data.get("core_x", ""),
		data.get("core_y", ""),
		data.get("outcome", ""),
		data.get("note", ""),
		data.get("component_id", data.get("gate_id", "")),
		data.get("segment_id", ""),
		data.get("collision_category", ""),
		data.get("result_reason", ""),
		data.get("branch", ""),
		data.get("sequence_version", ""),
	])
	_events_buffer.append(csv_row(row))

func log_impact(
	_elapsed_compat: float,
	_level_compat: String,
	_condition_compat: String,
	strength: float,
	damage: float,
	ball_pos: Vector2,
) -> void:
	log_event("collision", {
		"impact_strength": strength,
		"damage": damage,
		"core_x": ball_pos.x,
		"core_y": ball_pos.y,
	})

func log_condition_event(
	_elapsed_compat: float,
	slot: int,
	gain: float,
	note: String,
) -> void:
	var event_type: String = "perturb_off" if gain >= 0.999 else "perturb_on"
	log_event(event_type, {"slot": slot, "gain": gain, "note": note})

func flush() -> void:
	if _frames_file != null:
		for line: String in _frames_buffer:
			_frames_file.store_string(line + "\r\n")
		_frames_file.flush()
		_frames_buffer.clear()
	if _events_file != null:
		for line: String in _events_buffer:
			_events_file.store_string(line + "\r\n")
		_events_file.flush()
		_events_buffer.clear()

func close_session() -> void:
	if _trial_active:
		log_event("app_abort", {"outcome": "aborted"})
		end_trial("aborted", "session_closed_with_active_trial")
	flush()
	if _frames_file != null:
		_frames_file.close()
		_frames_file = null
	if _events_file != null:
		_events_file.close()
		_events_file = null

## 旧名称保留给外部脚本；明确表示关闭整个应用级 session。
func end_session() -> void:
	close_session()

func team_avg_force() -> float:
	return total_force_sum / float(sample_count) if sample_count > 0 else 0.0

func full_push_ratio() -> float:
	return float(full_push_count) / float(active_input_count) if active_input_count > 0 else 0.0

func fine_control_ratio() -> float:
	return float(fine_control_count) / float(active_input_count) if active_input_count > 0 else 0.0

func summary_dict() -> Dictionary:
	return {
		"avg_force": team_avg_force(),
		"full_push_ratio": full_push_ratio(),
		"fine_control_ratio": fine_control_ratio(),
		"log_samples": str(_paths.get("frames", "")),
		"log_events": str(_paths.get("events", "")),
		"log_session": str(_paths.get("session", "")),
		"session_id": _session_id,
		"trial_id": _trial_id,
		"life_id": _life_id,
		"protocol_version": _protocol_version,
		"data_directory": _session_dir,
		"results_directory": str(_paths.get("results_directory", "")),
		"qc_directory": str(_paths.get("qc_directory", "")),
		"data_export_ok": _last_export_ok,
		"data_export_message": _last_export_message,
		"data_export_finished_us": _last_export_finished_us,
	}

## 离线分析器稳定入口：路径、固定列和 RFC4180 编码器均可直接调用。
func output_paths() -> Dictionary:
	return _paths.duplicate()

## 创建实验数据根目录，供标题页“打开数据文件夹”使用。
func ensure_root() -> String:
	_ensure_directory(ROOT_DIR)
	return ROOT_DIR

## 规范路径：组号 / 开局时间 / raw、results 与按需 qc。
static func resolve_session_paths(session_dir: String) -> Dictionary:
	return make_nested_paths(session_dir)

static func make_nested_paths(session_dir: String) -> Dictionary:
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

static func schema_columns() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session": SESSION_COLUMNS.duplicate(),
		"frames": FRAME_COLUMNS.duplicate(),
		"events": EVENT_COLUMNS.duplicate(),
	}

static func csv_escape(value: Variant) -> String:
	if value == null:
		return ""
	var text: String
	if value is bool:
		text = "1" if bool(value) else "0"
	elif value is float:
		text = String.num(float(value), 9)
	else:
		text = str(value)
	if text.contains("\""):
		text = text.replace("\"", "\"\"")
	if text.contains(",") or text.contains("\"") or text.contains("\r") or text.contains("\n"):
		return "\"%s\"" % text
	return text

static func csv_row(values: Array[Variant]) -> String:
	var escaped: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		escaped.append(csv_escape(value))
	return ",".join(escaped)

func _ensure_session() -> bool:
	if not bool(GameState.get("experiment_mode")):
		return false
	if not _session_id.is_empty():
		return _frames_file != null and _events_file != null
	if not _allocate_session_directory():
		return false
	_session_start_us = Time.get_ticks_usec()
	_last_clock_us = _session_start_us
	_last_export_ok = false
	_last_export_message = "not_run"
	_last_export_finished_us = 0
	GameState.session_id = _session_id
	_frames_file = _open_new_csv(str(_paths["frames"]), FRAME_COLUMNS)
	_events_file = _open_new_csv(str(_paths["events"]), EVENT_COLUMNS)
	var session_file: FileAccess = _open_new_csv(str(_paths["session"]), SESSION_COLUMNS)
	if _frames_file == null or _events_file == null or session_file == null:
		push_error("ExperimentLog: failed to open session CSV files")
		close_session()
		return false
	var missing: PackedStringArray = PackedStringArray()
	for field: String in [
		"station_number", "dyad_id", "participant_A", "participant_B",
		"relation_condition", "protocol_version", "side_assignment",
	]:
		if not _has_property(GameState, field):
			missing.append(field)
	var app_version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if app_version.is_empty():
		app_version = "dev"
	var session_row: Array[Variant] = [
		SCHEMA_VERSION,
		app_version,
		_session_id,
		maxi(1, int(_identity_value("station_number", 1))),
		_identity_value("dyad_id", ""),
		_identity_value("participant_A", ""),
		_identity_value("participant_B", ""),
		_identity_value("relation_condition", ""),
		_identity_value("protocol_version", GameState.PROTOCOL_VERSION),
		_identity_value("side_assignment", ""),
		Time.get_datetime_string_from_system(true, false),
		OS.get_name(),
		InputHub.deadzone,
		InputHub.gamma,
		InputHub.f_max,
		Engine.physics_ticks_per_second,
		";".join(missing),
	]
	session_file.store_string(csv_row(session_row) + "\r\n")
	session_file.flush()
	session_file.close()
	return true

## 分配 user://experiments/station-<采集站>/dyad-<组号>/<UTC时间>/，同秒冲突时追加序号。
func _allocate_session_directory() -> bool:
	if not _ensure_directory(ROOT_DIR):
		push_error("ExperimentLog: cannot create experiments root")
		return false
	var station: int = maxi(1, int(_identity_value("station_number", 1)))
	var dyad: String = _safe_id(str(_identity_value("dyad_id", "UNSET")))
	var station_dir: String = ROOT_DIR.path_join("station-%d" % station)
	if not _ensure_directory(station_dir):
		push_error("ExperimentLog: cannot create station directory")
		return false
	var dyad_dir: String = station_dir.path_join("dyad-%s" % dyad)
	if not _ensure_directory(dyad_dir):
		push_error("ExperimentLog: cannot create dyad directory")
		return false
	var stamp: String = _utc_folder_stamp()
	for attempt: int in 32:
		var folder: String = stamp if attempt == 0 else "%s_%02d" % [stamp, attempt + 1]
		_session_dir = dyad_dir.path_join(folder)
		if DirAccess.dir_exists_absolute(_session_dir):
			continue
		_session_id = "%d-%s_%s" % [station, dyad, folder]
		_paths = make_nested_paths(_session_dir)
		if not _ensure_directory(str(_paths["raw_directory"])):
			_session_id = ""
			_session_dir = ""
			_paths = {}
			return false
		return true
	push_error("ExperimentLog: failed to allocate unique session directory")
	_session_id = ""
	_session_dir = ""
	_paths = {}
	return false

## UTC 文件夹名：2026-08-13_051600Z，便于按日期浏览。
func _utc_folder_stamp() -> String:
	var raw: String = Time.get_datetime_string_from_system(true, false)
	return "%sZ" % raw.replace(":", "").replace("T", "_")

func _ensure_directory(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK

func _open_new_csv(path: String, columns: PackedStringArray) -> FileAccess:
	if FileAccess.file_exists(path):
		push_error("ExperimentLog: refusing to overwrite %s" % path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		var header: Array[Variant] = []
		for column: String in columns:
			header.append(column)
		file.store_string(csv_row(header) + "\r\n")
	return file

## 启动时为上次未写 trial_end 的追加日志补恢复标记；绝不改写已有原始行。
func _recover_interrupted_sessions(root_path: String = ROOT_DIR) -> void:
	for session_directory: String in _session_directories_under(root_path):
		var paths: Dictionary = resolve_session_paths(session_directory)
		var path: String = str(paths["events"])
		var reader: FileAccess = FileAccess.open(path, FileAccess.READ)
		if reader == null or reader.get_length() <= 0:
			continue
		var header: PackedStringArray = reader.get_csv_line()
		var last: PackedStringArray = PackedStringArray()
		while reader.get_position() < reader.get_length():
			var row: PackedStringArray = reader.get_csv_line()
			if row.size() == header.size():
				last = row
		reader.close()
		var event_index: int = header.find("event_type")
		var trial_index: int = header.find("trial_id")
		if (
			last.is_empty()
			or event_index < 0
			or trial_index < 0
			or last[trial_index].is_empty()
			or last[event_index] == "trial_end"
		):
			continue
		var values: Array[Variant] = []
		for value: String in last:
			values.append(value)
		var monotonic_index: int = header.find("monotonic_time_us")
		if monotonic_index >= 0:
			values[monotonic_index] = maxi(
				int(last[monotonic_index]) + 1,
				Time.get_ticks_usec(),
			)
		values[event_index] = "aborted_recovered"
		var outcome_index: int = header.find("outcome")
		var note_index: int = header.find("note")
		if outcome_index >= 0:
			values[outcome_index] = "aborted"
		if note_index >= 0:
			values[note_index] = "recovered_on_next_start"
		var writer: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
		if writer == null:
			continue
		writer.seek_end()
		writer.store_string(csv_row(values) + "\r\n")
		values[event_index] = "trial_end"
		if note_index >= 0:
			values[note_index] = "aborted_recovered"
		if monotonic_index >= 0:
			values[monotonic_index] = int(values[monotonic_index]) + 1
		writer.store_string(csv_row(values) + "\r\n")
		writer.flush()
		writer.close()
		if not ExperimentAnalyzer.export_session(paths):
			push_warning(
				"ExperimentLog: recovered raw data but derived export failed for %s"
				% session_directory
			)

## 收集一层或两层下的 session 目录：experiments/dyad-*/<UTC>/。
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

func _session_directories_under(root_path: String) -> PackedStringArray:
	return session_directories_under(root_path)

static func _looks_like_session_dir(path: String) -> bool:
	return FileAccess.file_exists(path.path_join(RAW_FOLDER).path_join("events.csv"))

func _clock_us() -> int:
	var now: int = Time.get_ticks_usec()
	if now <= _last_clock_us:
		now = _last_clock_us + 1
	_last_clock_us = now
	return now

func _clock_snapshot(physics_frame: int) -> Dictionary:
	var now: int = _clock_us()
	return {
		"now": now,
		"session_ms": float(now - _session_start_us) / 1000.0,
		"trial_ms": float(now - _trial_start_us) / 1000.0,
		"physics_frame": physics_frame,
	}

func _clock_values(clock: Dictionary) -> Array[Variant]:
	return [
		SCHEMA_VERSION, _session_id, clock["now"], clock["session_ms"],
		clock["trial_ms"], clock["physics_frame"], _trial_id, _life_id,
		_level_id, _level_attempt_index, _protocol_version,
	]

func _slot_snapshot(slot: int) -> Dictionary:
	var sample: ForceMapper.Sample = InputHub.get_force_sample(slot)
	var kind: InputHub.SourceKind = InputHub.slot_kind(slot)
	var device_id: int = InputHub.slot_joy_id(slot)
	var connected: bool = kind != InputHub.SourceKind.NONE
	if kind == InputHub.SourceKind.JOYPAD:
		_known_device_slots[device_id] = slot
		connected = Input.get_connected_joypads().has(device_id)
	return {
		"sample": sample,
		"source": _source_name(kind),
		"device_id": device_id,
		"connected": connected,
		"raw_x": sample.raw.x, "raw_y": sample.raw.y,
		"cal_x": sample.calibrated.x, "cal_y": sample.calibrated.y,
		"m1": sample.m1, "m2": sample.m2, "gain": sample.gain,
		"fx": sample.force.x, "fy": sample.force.y, "f_mag": sample.force.length(),
	}

func _accumulate_sample(sample: ForceMapper.Sample) -> void:
	var magnitude: float = sample.force.length()
	sample_count += 1
	total_force_sum += magnitude
	var intensity: float = sample.m2 * sample.gain
	if intensity <= 0.02:
		return
	active_input_count += 1
	if intensity >= FULL_PUSH_THRESHOLD:
		full_push_count += 1
	elif intensity >= FINE_MIN and intensity <= FINE_MAX:
		fine_control_count += 1

func _participant_slot(participant: String) -> int:
	var assignment: Variant = _identity_value("side_assignment", "")
	if assignment is Dictionary:
		var mapped: String = str((assignment as Dictionary).get(participant, "P1")).to_upper()
		return 1 if mapped in ["P2", "1", "RIGHT"] else 0
	var text: String = str(assignment).to_upper().replace(" ", "")
	if participant == "A":
		for marker: String in ["A=P2", "A:P2", "A_P2", "A-RIGHT", "A_RIGHT"]:
			if text.contains(marker):
				return 1
		return 0
	return 1 - _participant_slot("A")

func _active_protocol_version() -> String:
	var value: String = str(_identity_value("protocol_version", GameState.PROTOCOL_VERSION))
	return value if not value.is_empty() else GameState.PROTOCOL_VERSION

func _identity_value(field: String, fallback: Variant) -> Variant:
	return GameState.get(field) if _has_property(GameState, field) else fallback

func _has_property(object: Object, field: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == field:
			return true
	return false

func _safe_id(value: String) -> String:
	var out: String = ""
	for character: String in value.to_upper():
		if character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			out += character
	return out.left(16) if not out.is_empty() else "UNSET"

func _source_name(kind: InputHub.SourceKind) -> String:
	match kind:
		InputHub.SourceKind.KEYBOARD_WASD:
			return "keyboard_wasd"
		InputHub.SourceKind.KEYBOARD_ARROWS:
			return "keyboard_arrows"
		InputHub.SourceKind.JOYPAD:
			return "joypad"
	return "none"

func _on_joy_hotplug(device_id: int, connected: bool) -> void:
	if not _trial_active:
		return
	var slot: int = InputHub.find_joypad_slot(device_id)
	if slot < 0:
		slot = int(_known_device_slots.get(device_id, -1))
	log_event("controller_reconnect" if connected else "controller_disconnect", {
		"device_id": device_id,
		"slot": slot,
	})
	if not connected:
		_known_device_slots.erase(device_id)

func _reset_trial_summary() -> void:
	total_force_sum = 0.0
	sample_count = 0
	full_push_count = 0
	fine_control_count = 0
	active_input_count = 0
	_frames_buffer.clear()
	_events_buffer.clear()
	_flush_left = FLUSH_INTERVAL_S

func _exit_tree() -> void:
	close_session()
