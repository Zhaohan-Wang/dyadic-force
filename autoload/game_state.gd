extends Node
## 全局游戏状态：设置、当前关卡、通关进度。
## 设置用 ConfigFile 持久化到 user://settings.cfg。

## 设置变更时发出（供 UI / 分屏等订阅）
signal settings_changed

## 当前选中的关卡定义（进入 LevelScene 前由选关界面写入）
var current_level: LevelDef = null
## 上一关结算结果（ResultsScreen 读取）
var last_result: Dictionary = {}
## 当前运行的去标识化实验信息；只接受短编号，禁止姓名和自由文本。
var dyad_id: String = ""
var participant_A: String = ""
var participant_B: String = ""
## 关系条件：unspecified / strangers / friends。正式锁定必须二选一。
var relation_condition: String = "unspecified"
## 单一标准协议版本；不再使用全局 Baseline/Perturbation 分组。
var protocol_version: String = "pilot-1.0"
## A 对应的设备槽位；0=P1/左屏，1=P2/右屏。B 自动使用另一个槽位。
var participant_a_slot: int = 0
## CSV/日志侧读取的稳定分配编码。
var side_assignment: String = "A=P1;B=P2"
## 完成录入后锁定元数据，选关页只能读取。
var experiment_setup_locked: bool = false
## 当前试次会话 ID（日志文件名用）
var session_id: String = ""

## 设置项
var shake_enabled: bool = true
var vignette_enabled: bool = true
var master_volume: float = 1.0
## 手柄震动总强度：0=关闭，默认 0.85，设置页可分档调节。
var haptic_strength: float = 0.85
## 界面语言：默认中文；"en" 为英文。
var language: String = "zh"
## 实验模式：开启后走录入页并写实验 CSV；默认关闭。
var experiment_mode: bool = false
## 调试模式：选关页教学关下显示物理滑条；默认关闭。
var debug_mode: bool = false
## 本机的持久化采集站编号；所有新组号自动带入，不在录入页重复选择。
var station_number: int = 1

## 已通关的关卡 ID 列表
var cleared_levels: PackedStringArray = PackedStringArray()

const SETTINGS_PATH: String = "user://settings.cfg"
const PROGRESS_PATH: String = "user://progress.cfg"
const LANGUAGE_ZH: String = "zh"
const LANGUAGE_EN: String = "en"
const ID_MAX_LENGTH: int = 16
const PROTOCOL_VERSION: String = "pilot-1.0"
const ID_ALLOWED: String = "0123456789SDAB-"
const RELATION_CONDITIONS: PackedStringArray = [
	"unspecified",
	"strangers",
	"friends",
]
const LOCKABLE_RELATIONS: PackedStringArray = [
	"strangers",
	"friends",
]

## 关卡资源继续保存稳定的英文实验文本，界面显示时按当前语言映射。
const CONTENT_ZH: Dictionary[String, String] = {
	"TUTORIAL": "教学关",
	"LEVEL 1 - GATE RUN": "第 1 关 · 三门冲关",
	"LEVEL 2 - SWITCHBACK": "第 2 关 · 折返原野",
	"LEVEL 3 - WOODLAND": "第 3 关 · 林间弯道",
	"LEVEL 4 - UNSTEADY TRAIL": "第 4 关 · 不稳小径",
	"LEVEL 5 - FORKED TRAILS": "第 5 关 · 分叉小径",
	"FULL PUSH TO START AND ACCELERATE": "将摇杆推到底，开始移动并加速",
	"USE HALF PUSH TO STEER AND AIM": "使用中等力度微调方向",
	"RELEASE EARLY TO BRAKE BEFORE TURNS": "转弯前提前松开摇杆进行减速",
	"PUSH THE SAME WAY TO ROLL TOGETHER": "两人同向推动，让球向前滚动",
	"PUSH OPPOSITE WAYS TO SPIN IN PLACE": "两人反向推动，让球原地旋转",
	"HARD HITS HURT THE BALL - BE CAREFUL": "猛烈碰撞会伤害球，请小心控制",
	"PARK THE BALL ON THE SWIRLING PORTAL": "将球停在旋转的传送门上",
	"OFFICIAL LEVELS ARE TIMED!": "正式关卡有时间限制！",
	"REACH THE PORTAL WITHIN 60 SECONDS": "请在 60 秒内到达传送门",
	"REACH THE PORTAL WITHIN 80 SECONDS": "请在 80 秒内到达传送门",
	"REACH THE PORTAL WITHIN 90 SECONDS": "请在 90 秒内到达传送门",
	"REACH THE PORTAL WITHIN 120 SECONDS.": "请在 120 秒内到达传送门。",
	"OR THE RUN IS OVER.": "否则本次挑战结束。",
	"BUILD SPEED TO BREAK THROUGH THE GATES.": "加速冲破沿途的大门。",
	"LONG STRAIGHTS LEAD INTO SHARP TURNS.": "长直道之后是急转弯。",
	"FOLLOW THE TRAIL THROUGH THE WOODS.": "沿着林间小径前进。",
	"CONTROL MAY FEEL UNSTEADY HERE.": "这里的控制可能会不太稳定。",
	"FIND YOUR WAY THROUGH THE FORKED TRAILS.": "在分叉小径中找到你们的路线。",
}

## 关卡推进顺序（选关列表与结算"下一关"共用）
const LEVEL_ORDER: PackedStringArray = [
	"res://levels/practice.tres",
	"res://levels/level_1.tres",
	"res://levels/level_2.tres",
	"res://levels/level_3.tres",
	"res://levels/level_4.tres",
	"res://levels/level_5.tres",
]

## 按 level_id 查找下一关资源路径；已是最后一关返回空串
func next_level_path(level_id: String) -> String:
	for i: int in LEVEL_ORDER.size():
		var def: LevelDef = load(LEVEL_ORDER[i]) as LevelDef
		if def != null and def.level_id == level_id:
			if i + 1 < LEVEL_ORDER.size():
				return LEVEL_ORDER[i + 1]
			return ""
	return ""

func _ready() -> void:
	load_settings()
	load_progress()
	PhysicsTuning.ensure_loaded()

## 开始游戏后的第一站：实验模式进录入页，否则直达配对。
func start_flow_scene() -> String:
	if experiment_mode:
		return "res://scenes/experiment_setup_screen.tscn"
	return "res://scenes/pairing_screen.tscn"

## 配对页返回目标：实验模式回录入，否则回标题。
func pairing_back_scene() -> String:
	if experiment_mode:
		return "res://scenes/experiment_setup_screen.tscn"
	return "res://scenes/title_screen.tscn"

## 只保留去标识编号允许的字符：数字、S/D/A/B 与连字符。
func sanitize_experiment_id(raw_value: String) -> String:
	var result: String = ""
	for index: int in raw_value.length():
		var character: String = raw_value.substr(index, 1).to_upper()
		if ID_ALLOWED.contains(character):
			result += character
		if result.length() >= ID_MAX_LENGTH:
			break
	while result.begins_with("-"):
		result = result.substr(1)
	while result.ends_with("-"):
		result = result.substr(0, result.length() - 1)
	return result

## 唯一组号规范为 S<本站编号>-D<组内序号>；录入页只传入数字。
func normalize_dyad_id(raw_value: String) -> String:
	var clean: String = raw_value.strip_edges().to_upper()
	if clean.is_empty():
		return ""
	var sequence: String = clean
	var parsed_station: int = station_number
	if clean.begins_with("S"):
		var separator_index: int = clean.find("-D")
		if separator_index <= 1:
			return ""
		var station_digits: String = clean.substr(1, separator_index - 1)
		sequence = clean.substr(separator_index + 2)
		if not _is_positive_digit_string(station_digits):
			return ""
		parsed_station = station_digits.to_int()
	for index: int in sequence.length():
		var character: String = sequence.substr(index, 1)
		if character < "0" or character > "9":
			return ""
	if not _is_positive_digit_string(sequence):
		return ""
	return "S%d-D%03d" % [parsed_station, sequence.to_int()]

func _is_positive_digit_string(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var character: String = value.substr(index, 1)
		if character < "0" or character > "9":
			return false
	return value.to_int() > 0

## 由组号派生稳定参与者编号，例如 S1-D001-A / S1-D001-B。
func default_participant_id(raw_dyad: String, letter: String) -> String:
	var dyad: String = normalize_dyad_id(raw_dyad)
	var tag: String = letter.to_upper()
	if dyad.is_empty() or tag not in ["A", "B"]:
		return ""
	return "%s-%s" % [dyad, tag]

## 奇数 A=P1，偶数 A=P2。无法解析时默认 A=P1。
func default_a_slot_for_dyad(raw_dyad: String) -> int:
	var canonical: String = normalize_dyad_id(raw_dyad)
	var d_index: int = canonical.rfind("D")
	var digits: String = canonical.substr(d_index + 1) if d_index >= 0 else ""
	if digits.is_empty():
		return 0
	return 0 if digits.to_int() % 2 == 1 else 1

func is_default_participant_id(raw_dyad: String, raw_participant: String, letter: String) -> bool:
	return sanitize_experiment_id(raw_participant) == default_participant_id(raw_dyad, letter)

## 校验并锁定实验信息。参与者编号与侧别只由组号生成，不能手工覆盖。
func lock_experiment_setup(next_dyad_id: String, next_relation: String) -> bool:
	var clean_dyad: String = normalize_dyad_id(next_dyad_id)
	if clean_dyad.is_empty() or not LOCKABLE_RELATIONS.has(next_relation):
		return false
	dyad_id = clean_dyad
	participant_A = default_participant_id(clean_dyad, "A")
	participant_B = default_participant_id(clean_dyad, "B")
	relation_condition = next_relation
	protocol_version = PROTOCOL_VERSION
	participant_a_slot = default_a_slot_for_dyad(clean_dyad)
	side_assignment = "A=P1;B=P2" if participant_a_slot == 0 else "A=P2;B=P1"
	experiment_setup_locked = true
	return true

func _digits_only(raw_value: String) -> String:
	var digits: String = ""
	for index: int in raw_value.length():
		var character: String = raw_value.substr(index, 1)
		if character >= "0" and character <= "9":
			digits += character
	return digits

## 返回设备槽位对应的参与者标签（A/B）。
func participant_letter_for_slot(slot: int) -> String:
	return "A" if slot == participant_a_slot else "B"

## 返回设备槽位对应的去标识化参与者编号。
func participant_id_for_slot(slot: int) -> String:
	return participant_A if slot == participant_a_slot else participant_B

func screen_side_for_slot(slot: int) -> String:
	return ui("左屏", "LEFT") if slot == 0 else ui("右屏", "RIGHT")

## 标记某关已通关
func mark_cleared(level_id: String) -> void:
	if not cleared_levels.has(level_id):
		cleared_levels.append(level_id)
		save_progress()

## 查询某关是否已通关
func is_cleared(level_id: String) -> bool:
	return cleared_levels.has(level_id)

## 从磁盘加载设置
func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	shake_enabled = bool(cfg.get_value("audio_visual", "shake_enabled", true))
	vignette_enabled = bool(cfg.get_value("audio_visual", "vignette_enabled", true))
	master_volume = float(cfg.get_value("audio_visual", "master_volume", 1.0))
	haptic_strength = clampf(
		float(cfg.get_value("audio_visual", "haptic_strength", 0.85)),
		0.0,
		1.0,
	)
	language = str(cfg.get_value("general", "language", LANGUAGE_ZH))
	if language != LANGUAGE_EN:
		language = LANGUAGE_ZH
	experiment_mode = bool(cfg.get_value("modes", "experiment_mode", false))
	debug_mode = bool(cfg.get_value("modes", "debug_mode", false))
	station_number = maxi(1, int(cfg.get_value("experiment", "station_number", 1)))

## 保存设置到磁盘
func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio_visual", "shake_enabled", shake_enabled)
	cfg.set_value("audio_visual", "vignette_enabled", vignette_enabled)
	cfg.set_value("audio_visual", "master_volume", master_volume)
	cfg.set_value("audio_visual", "haptic_strength", haptic_strength)
	cfg.set_value("general", "language", language)
	cfg.set_value("modes", "experiment_mode", experiment_mode)
	cfg.set_value("modes", "debug_mode", debug_mode)
	cfg.set_value("experiment", "station_number", maxi(1, station_number))
	cfg.save(SETTINGS_PATH)
	settings_changed.emit()

## 根据当前语言返回对应界面文本。
func ui(zh_text: String, en_text: String) -> String:
	return zh_text if language == LANGUAGE_ZH else en_text

## 切换并持久化界面语言。
func set_language(next_language: String) -> void:
	language = LANGUAGE_EN if next_language == LANGUAGE_EN else LANGUAGE_ZH
	save_settings()

## 翻译关卡资源中的稳定英文文本；未登记内容原样返回。
func localize_content(source: String) -> String:
	if language == LANGUAGE_EN:
		return source
	return CONTENT_ZH.get(source, source)

## 加载通关进度
func load_progress() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		return
	var arr: Variant = cfg.get_value("progress", "cleared", PackedStringArray())
	if arr is PackedStringArray:
		cleared_levels = arr as PackedStringArray

## 保存通关进度
func save_progress() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("progress", "cleared", cleared_levels)
	cfg.save(PROGRESS_PATH)
