class_name LevelDef
extends Resource
## 关卡数据定义：练习关与正式关共用同一套结构，差异全部来自字段取值。
## 一个关卡对应一个 .tres 文件，由 LevelScene 消费。

## 关卡显示名（教程 / 第 1 关 …）
@export var level_name: String = "关卡"
## 关卡唯一 ID（用于进度存档）
@export var level_id: String = "level_1"
## 实验挑战类型（一关一主题）
@export_enum(
	"tutorial",
	"joint_start",
	"joint_brake",
	"turn_coord",
	"imbalance",
	"route_choice"
) var challenge_type: String = "joint_start"
## 岛屿尺寸（瓦片数）
@export var island_size: Vector2i = Vector2i(30, 18)
## 障碍布局随机种子
@export var layout_seed: int = 20260801
## 障碍密度倍率（1.0 = 默认，越大障碍越多；lane 模式忽略）
@export var obstacle_density: float = 1.0
## 布局风格：scatter = 随机散布；lane = 手工动线；author = 按 level_id 分发手工布局
@export_enum("scatter", "lane", "author") var layout_style: String = "scatter"
## 出生点 = 重生点（世界像素坐标）
@export var spawn_point: Vector2 = Vector2(240.0, 144.0)
## 终点位置（世界像素坐标）
@export var goal_point: Vector2 = Vector2(400.0, 144.0)
## 分析与地图共用的手工中心线（按出生点到终点顺序）。
@export var route_centerline: PackedVector2Array = PackedVector2Array()
## 合法走廊半宽（像素）；球心到中心线距离不超过此值即在界内。
@export var route_corridor_half_width: float = 96.0
## 完成方向（世界坐标单位向量），用于复核终点附近运动方向。
@export var route_completion_direction: Vector2 = Vector2.RIGHT
## 限时（秒）；0 = 不限时（练习关）
@export var time_limit: float = 0.0
## 目标完成时长（秒），用于试玩校准；不影响运行时倒计时
@export var target_duration_s: float = 80.0
## 球的最大生命值（整心格数；HUD 固定显示 3 格，默认 3）
@export var ball_max_hp: float = 3.0
## 死亡重生时正式关扣除的时间（秒）；练习关忽略
@export var death_time_penalty: float = 5.0
## 练习关教程提示序列（正式关留空）
@export var tutorial_steps: PackedStringArray = PackedStringArray()
## 开场须知弹窗文本（每个元素一行；留空 = 不弹窗）
@export var intro_lines: PackedStringArray = PackedStringArray()
## 旧版固定时间窗扰动（已停用；保留字段以免旧 .tres 丢失）
@export var dampen_window: Vector2 = Vector2.ZERO
## 是否为练习关（影响 HUD：隐藏倒计时、显示已用时）
@export var is_practice: bool = false

## ---- 五关扩展组件配置 ----
## 可撞门列表（第 1 关）
@export var gates: Array[GateDef] = []
## 不可见实验路段列表
@export var segments: Array[SegmentDef] = []
## 岔路追踪列表（第 5 关）
@export var choice_forks: Array[ChoiceForkDef] = []
## 扰动候选路段 ID（须对应 segments 中 perturb_candidate）
@export var perturb_candidate_ids: PackedStringArray = PackedStringArray()
## 扰动隐藏序列版本（写入 session / 事件，保证可复现）
@export var perturb_sequence_version: String = "v1"
## 扰动序列种子（与 sequence_version 共同决定 A/B 顺序）
@export var perturb_sequence_seed: int = 20260813
## 目标成功扰动次数
@export var perturb_target_count: int = 2
## 为 true 时按时间循环扰动，不等人走进候选路段（第 4 关「从头扰到尾」）
@export var perturb_continuous: bool = false
## 单次扰动持续（秒）下限
@export var perturb_duration_min_s: float = 2.0
## 单次扰动持续（秒）上限
@export var perturb_duration_max_s: float = 3.0
## 输入增益下限（扰动时）
@export var perturb_gain_min: float = 0.55
## 输入增益上限（扰动时）
@export var perturb_gain_max: float = 0.65
## 两次扰动最小间隔（秒）
@export var perturb_min_gap_s: float = 5.0
## 被扰动一侧的力方向侧偏角下限（度）；0 = 只衰减幅值
@export var perturb_lateral_deg_min: float = 0.0
## 被扰动一侧的力方向侧偏角上限（度）
@export var perturb_lateral_deg_max: float = 0.0
