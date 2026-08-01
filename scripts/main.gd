extends Node2D
## 旧主场景入口（兼容）。正式流程从 TitleScreen 开始。
## 直接运行 main.tscn 时跳进练习关。

func _ready() -> void:
	var def: LevelDef = load("res://levels/practice.tres") as LevelDef
	GameState.current_level = def
	# 无转场，避免与本场景并存
	get_tree().change_scene_to_file("res://scenes/level.tscn")
