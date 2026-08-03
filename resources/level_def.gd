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
## 障碍密度倍率（1.0 = 默认，越大障碍越多；lane 模式忽略）
@export var obstacle_density: float = 1.0
## 布局风格：scatter = 随机散布；lane = 手工动线（左出生 → 中间少量障碍 → 右传送门）；
## author = 按 level_id 分发的手工关卡布局（先留通道再摆障碍，保证球一定能过）
@export_enum("scatter", "lane", "author") var layout_style: String = "scatter"
## 出生点 = 重生点（世界像素坐标）
@export var spawn_point: Vector2 = Vector2(240.0, 144.0)
## 终点位置（世界像素坐标）
@export var goal_point: Vector2 = Vector2(400.0, 144.0)
## 限时（秒）；0 = 不限时（练习关）
@export var time_limit: float = 0.0
## 球的最大生命值（整心格数；HUD 固定显示 3 格，默认 3）
@export var ball_max_hp: float = 3.0
## 死亡重生时正式关扣除的时间（秒）；练习关忽略
@export var death_time_penalty: float = 5.0
## 练习关教程提示序列（正式关留空）
@export var tutorial_steps: PackedStringArray = PackedStringArray()
## 开场须知弹窗文本（每个元素一行；留空 = 不弹窗）
## 弹出期间输入冻结、计时不开始，玩家按任意键确认后关卡才正式开始
@export var intro_lines: PackedStringArray = PackedStringArray()
## “输入缩减”时段（x = 开始秒，y = 结束秒，按已用时间计；ZERO = 无此机制）
## 时段内随机把 A 或 B 的输入缩减到约 65%，每段持续约 3 秒并交替换人
@export var dampen_window: Vector2 = Vector2.ZERO
## 是否为练习关（影响 HUD：隐藏倒计时、显示已用时）
@export var is_practice: bool = false
