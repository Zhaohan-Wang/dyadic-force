class_name ChoiceForkDef
extends Resource
## 第 5 关隐藏岔路追踪配置：入口区、两支方向与确认线。

## 岔路唯一 ID
@export var fork_id: String = "fork_1"
## 入口观察区（球进入后开始读持续输入偏好）
@export var approach_rect_position: Vector2 = Vector2.ZERO
@export var approach_rect_size: Vector2 = Vector2(200.0, 200.0)
## 左支（或第一支）方向单位向量
@export var branch_a_direction: Vector2 = Vector2.LEFT
## 右支（或第二支）方向单位向量
@export var branch_b_direction: Vector2 = Vector2.RIGHT
## 分支 A 确认线：线段两端点
@export var commit_a_from: Vector2 = Vector2.ZERO
@export var commit_a_to: Vector2 = Vector2.ZERO
## 分支 B 确认线：线段两端点
@export var commit_b_from: Vector2 = Vector2.ZERO
@export var commit_b_to: Vector2 = Vector2.ZERO
## 哪一支是短窄风险路线："A" 或 "B"
@export_enum("A", "B") var short_narrow_branch: String = "A"
## 分支标签（写入日志）：默认 left/right 语义由方向决定
@export var branch_a_label: String = "narrow"
@export var branch_b_label: String = "wide"

## 入口观察区矩形
func approach_rect() -> Rect2:
	return Rect2(approach_rect_position, approach_rect_size)
