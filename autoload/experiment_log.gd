extends Node
## 实验日志：缓冲式 CSV，记录每物理帧输入/力与碰撞事件。
## 路径：user://experiment_logs/<session>_<level>_samples.csv / _events.csv

const LOG_DIR: String = "user://experiment_logs"
## 满推判定阈值（m2·gain）
const FULL_PUSH_THRESHOLD: float = 0.90
## 中段精细控制区间
const FINE_MIN: float = 0.20
const FINE_MAX: float = 0.75
## 磁盘刷新间隔（秒）
const FLUSH_INTERVAL_S: float = 1.0

var _active: bool = false
var _sample_path: String = ""
var _event_path: String = ""
var _sample_file: FileAccess = null
var _event_file: FileAccess = null
var _sample_buffer: PackedStringArray = PackedStringArray()
var _event_buffer: PackedStringArray = PackedStringArray()
var _flush_left: float = FLUSH_INTERVAL_S

## 团队级汇总（结算页用）
var total_force_sum: float = 0.0
var sample_count: int = 0
var full_push_count: int = 0
var fine_control_count: int = 0
var active_input_count: int = 0

func _process(delta: float) -> void:
	if not _active:
		return
	_flush_left -= delta
	if _flush_left <= 0.0:
		_flush_left = FLUSH_INTERVAL_S
		_flush()

## 开始一局日志；session_id 为空时自动生成。
func begin_session(level_id: String, condition: String) -> void:
	end_session()
	if GameState.session_id == "":
		GameState.session_id = Time.get_datetime_string_from_system().replace(":", "-")
	var session: String = GameState.session_id
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir != null:
		user_dir.make_dir_recursive("experiment_logs")
	_sample_path = "%s/%s_%s_samples.csv" % [LOG_DIR, session, level_id]
	_event_path = "%s/%s_%s_events.csv" % [LOG_DIR, session, level_id]
	_sample_file = FileAccess.open(_sample_path, FileAccess.WRITE)
	_event_file = FileAccess.open(_event_path, FileAccess.WRITE)
	if _sample_file == null or _event_file == null:
		push_error("ExperimentLog: failed to open log files")
		_active = false
		return
	_sample_file.store_line(
		"session,level_id,condition,elapsed,slot,source,joy_id,"
		+ "raw_x,raw_y,cal_x,cal_y,m,m1,m2,gain,fx,fy,f_mag,"
		+ "ball_x,ball_y,vx,vy,omega,deadzone,gamma,f_max"
	)
	_event_file.store_line(
		"session,level_id,condition,elapsed,event_type,"
		+ "slot,gain,impact_strength,damage,ball_x,ball_y,note"
	)
	total_force_sum = 0.0
	sample_count = 0
	full_push_count = 0
	fine_control_count = 0
	active_input_count = 0
	_sample_buffer.clear()
	_event_buffer.clear()
	_flush_left = FLUSH_INTERVAL_S
	_active = true
	# 记录开局条件
	log_condition_event(0.0, -1, 1.0, "session_start:%s" % condition)

## 每物理帧写入两名玩家的力采样。
func log_frame(
	elapsed: float,
	level_id: String,
	condition: String,
	ball: RigidBody2D,
) -> void:
	if not _active or ball == null:
		return
	for slot: int in 2:
		var sample: ForceMapper.Sample = InputHub.get_force_sample(slot)
		var kind: InputHub.SourceKind = InputHub.slot_kind(slot)
		var source: String = _source_name(kind)
		var joy_id: int = InputHub.slot_joy_id(slot)
		var f_mag: float = sample.force.length()
		var line: String = "%s,%s,%s,%.4f,%d,%s,%d," % [
			GameState.session_id, level_id, condition, elapsed, slot, source, joy_id
		]
		line += "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f," % [
			sample.raw.x, sample.raw.y,
			sample.calibrated.x, sample.calibrated.y,
			sample.m, sample.m1, sample.m2, sample.gain,
			sample.force.x, sample.force.y, f_mag,
		]
		line += "%.3f,%.3f,%.3f,%.3f,%.4f,%.3f,%.3f,%.3f" % [
			ball.global_position.x, ball.global_position.y,
			ball.linear_velocity.x, ball.linear_velocity.y,
			ball.angular_velocity,
			InputHub.deadzone, InputHub.gamma, InputHub.f_max,
		]
		_sample_buffer.append(line)
		# 团队级汇总（两槽相加）
		sample_count += 1
		total_force_sum += f_mag
		var intensity: float = sample.m2 * sample.gain
		if intensity > 0.02:
			active_input_count += 1
			if intensity >= FULL_PUSH_THRESHOLD:
				full_push_count += 1
			elif intensity >= FINE_MIN and intensity <= FINE_MAX:
				fine_control_count += 1

## 记录碰撞事件。
func log_impact(
	elapsed: float,
	level_id: String,
	condition: String,
	strength: float,
	damage: float,
	ball_pos: Vector2,
) -> void:
	if not _active:
		return
	_event_buffer.append(
		"%s,%s,%s,%.4f,impact,-1,1.0,%.4f,%.4f,%.3f,%.3f," % [
			GameState.session_id, level_id, condition, elapsed,
			strength, damage, ball_pos.x, ball_pos.y,
		]
	)

## 记录条件/增益切换事件。
func log_condition_event(
	elapsed: float,
	slot: int,
	gain: float,
	note: String,
) -> void:
	if not _active:
		return
	var level_id: String = ""
	if GameState.current_level != null:
		level_id = GameState.current_level.level_id
	_event_buffer.append(
		"%s,%s,%s,%.4f,condition,%d,%.4f,0,0,0,0,%s" % [
			GameState.session_id, level_id, GameState.experiment_condition,
			elapsed, slot, gain, note,
		]
	)

## 结束并落盘。
func end_session() -> void:
	if not _active and _sample_file == null:
		return
	_flush()
	if _sample_file != null:
		_sample_file.close()
		_sample_file = null
	if _event_file != null:
		_event_file.close()
		_event_file = null
	_active = false

## 团队平均力度（实验单位）。
func team_avg_force() -> float:
	if sample_count <= 0:
		return 0.0
	return total_force_sum / float(sample_count)

## 满推占比（相对有输入帧）。
func full_push_ratio() -> float:
	if active_input_count <= 0:
		return 0.0
	return float(full_push_count) / float(active_input_count)

## 中段精细控制占比（相对有输入帧）。
func fine_control_ratio() -> float:
	if active_input_count <= 0:
		return 0.0
	return float(fine_control_count) / float(active_input_count)

## 汇总字典，写入 last_result。
func summary_dict() -> Dictionary:
	return {
		"avg_force": team_avg_force(),
		"full_push_ratio": full_push_ratio(),
		"fine_control_ratio": fine_control_ratio(),
		"log_samples": _sample_path,
		"log_events": _event_path,
		"experiment_condition": GameState.experiment_condition,
	}

func _flush() -> void:
	if _sample_file != null:
		for line: String in _sample_buffer:
			_sample_file.store_line(line)
		_sample_file.flush()
		_sample_buffer.clear()
	if _event_file != null:
		for line: String in _event_buffer:
			_event_file.store_line(line)
		_event_file.flush()
		_event_buffer.clear()

func _source_name(kind: InputHub.SourceKind) -> String:
	match kind:
		InputHub.SourceKind.KEYBOARD_WASD:
			return "keyboard_wasd"
		InputHub.SourceKind.KEYBOARD_ARROWS:
			return "keyboard_arrows"
		InputHub.SourceKind.JOYPAD:
			return "joypad"
	return "none"

func _exit_tree() -> void:
	end_session()
