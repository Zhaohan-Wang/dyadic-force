extends Node
## 全局游戏状态：设置、当前关卡、通关进度。
## 设置用 ConfigFile 持久化到 user://settings.cfg。

## 设置变更时发出（供 UI / 分屏等订阅）
signal settings_changed

## 当前选中的关卡定义（进入 LevelScene 前由选关界面写入）
var current_level: LevelDef = null
## 上一关结算结果（ResultsScreen 读取）
var last_result: Dictionary = {}

## 设置项
var shake_enabled: bool = true
var vignette_enabled: bool = true
var master_volume: float = 1.0

## 已通关的关卡 ID 列表
var cleared_levels: PackedStringArray = PackedStringArray()

const SETTINGS_PATH: String = "user://settings.cfg"
const PROGRESS_PATH: String = "user://progress.cfg"

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

## 保存设置到磁盘
func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio_visual", "shake_enabled", shake_enabled)
	cfg.set_value("audio_visual", "vignette_enabled", vignette_enabled)
	cfg.set_value("audio_visual", "master_volume", master_volume)
	cfg.save(SETTINGS_PATH)
	settings_changed.emit()

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
