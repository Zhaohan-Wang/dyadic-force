class_name LevelDef
extends Resource
## 关卡数据定义：练习关与正式关共用同一套结构，差异全部来自字段取值。
## 一个关卡对应一个 .tres 文件，由 LevelScene 消费。

## 关卡显示名（教程 / 第 1 关 …）
@export var level_name: String = "关卡"
## 关卡唯一 ID（用于进度存档）
@export var level_id: String = "level_1"
## 岛屿尺寸（瓦片数）
@export var island_size: Vector2i = Vector2i(30, 18)
## 障碍布局随机种子
@export var layout_seed: int = 20260801
## 障碍密度倍率（1.0 = 默认，越大障碍越多）
@export var obstacle_density: float = 1.0
## 出生点 = 重生点（世界像素坐标）
@export var spawn_point: Vector2 = Vector2(240.0, 144.0)
## 终点位置（世界像素坐标）
@export var goal_point: Vector2 = Vector2(400.0, 144.0)
## 限时（秒）；0 = 不限时（练习关）
@export var time_limit: float = 0.0
## 球的最大生命值
@export var ball_max_hp: float = 100.0
## 死亡重生时正式关扣除的时间（秒）；练习关忽略
@export var death_time_penalty: float = 5.0
## 练习关教程提示序列（正式关留空）
@export var tutorial_steps: PackedStringArray = PackedStringArray()
## 是否为练习关（影响 HUD：隐藏倒计时、显示已用时）
@export var is_practice: bool = false
