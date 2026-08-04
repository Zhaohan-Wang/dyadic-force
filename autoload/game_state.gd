extends Node
## 全局游戏状态：设置、当前关卡、通关进度。
## 设置用 ConfigFile 持久化到 user://settings.cfg。

## 设置变更时发出（供 UI / 分屏等订阅）
signal settings_changed

## 当前选中的关卡定义（进入 LevelScene 前由选关界面写入）
var current_level: LevelDef = null
## 上一关结算结果（ResultsScreen 读取）
var last_result: Dictionary = {}
## 实验条件：baseline = 关闭第 3 关输入缩减；perturbation = 启用
var experiment_condition: String = "baseline"
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

## 已通关的关卡 ID 列表
var cleared_levels: PackedStringArray = PackedStringArray()

const SETTINGS_PATH: String = "user://settings.cfg"
const PROGRESS_PATH: String = "user://progress.cfg"
const LANGUAGE_ZH: String = "zh"
const LANGUAGE_EN: String = "en"

## 关卡资源继续保存稳定的英文实验文本，界面显示时按当前语言映射。
const CONTENT_ZH: Dictionary[String, String] = {
	"TUTORIAL": "教学关",
	"LEVEL 1 - MEADOW": "第 1 关 · 草地",
	"LEVEL 2 - HEDGE MAZE": "第 2 关 · 树篱迷宫",
	"LEVEL 3 - FINAL DASH": "第 3 关 · 最终冲刺",
	"FULL PUSH TO START AND ACCELERATE": "将摇杆推到底，开始移动并加速",
	"USE HALF PUSH TO STEER AND AIM": "使用中等力度微调方向",
	"RELEASE EARLY TO BRAKE BEFORE TURNS": "转弯前提前松开摇杆进行减速",
	"PUSH THE SAME WAY TO ROLL TOGETHER": "两人同向推动，让球向前滚动",
	"PUSH OPPOSITE WAYS TO SPIN IN PLACE": "两人反向推动，让球原地旋转",
	"HARD HITS HURT THE BALL - BE CAREFUL": "猛烈碰撞会伤害球，请小心控制",
	"PARK THE BALL ON THE SWIRLING PORTAL": "将球停在旋转的传送门上",
	"OFFICIAL LEVELS ARE TIMED!": "正式关卡有时间限制！",
	"REACH THE PORTAL WITHIN 60 SECONDS": "请在 60 秒内到达传送门",
	"OR THE RUN IS OVER.": "否则本次挑战结束。",
	"THE ROUTE GETS LONGER AND TRICKIER.": "路线会变得更长、更复杂。",
	"FOLLOW THE ARROWS ON THE GROUND.": "请跟随地面上的箭头。",
	"SIGNAL JAM ALERT!": "信号干扰警告！",
	"ONLY IN PERTURBATION CONDITION:": "仅在扰动实验条件下：",
	"FROM 5S TO 35S ONE INPUT DROPS TO ~65%.": "第 5～35 秒，一名玩家的输入会降至约 65%。",
	"BASELINE RUNS HAVE NO SIGNAL JAM.": "基线条件下不会出现信号干扰。",
}

## 关卡推进顺序（选关列表与结算"下一关"共用）
const LEVEL_ORDER: PackedStringArray = [
	"res://levels/practice.tres",
	"res://levels/level_1.tres",
	"res://levels/level_2.tres",
	"res://levels/level_3.tres",
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

## 保存设置到磁盘
func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio_visual", "shake_enabled", shake_enabled)
	cfg.set_value("audio_visual", "vignette_enabled", vignette_enabled)
	cfg.set_value("audio_visual", "master_volume", master_volume)
	cfg.set_value("audio_visual", "haptic_strength", haptic_strength)
	cfg.set_value("general", "language", language)
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
