class_name GateDef
extends Resource
## 可撞门配置：位置、门轴与判定阈值。第 1、3、5 关在用。

## 门唯一 ID（写入日志 component_id）
@export var gate_id: String = "gate_1"
## 门中心世界坐标（像素）
@export var position: Vector2 = Vector2.ZERO
## 门轴（门横跨的方向轴，通常填该处前进方向）。
## 正负号不限制撞法：实际穿门方向由球从哪一侧撞来解算，左→右与右→左都成立。
@export var normal: Vector2 = Vector2.RIGHT
## 有效通过口宽度（像素）
@export var opening_width: float = 180.0
## 门板厚度（像素）
@export var thickness: float = 18.0
## 碰撞前正向速度阈值（像素/秒）；第 1 关三门约为 240 / 260 / 300
@export var speed_threshold: float = 240.0
## 双方施力方向余弦下限（0～1）
@export var direction_cosine_min: float = 0.60
## 窗口内各自有效发力占比下限（0～1）
@export var activity_ratio_min: float = 0.50
## 判定窗口时长（秒）
@export var window_s: float = 0.40
