class_name SegmentDef
extends Resource
## 不可见实验路段：仅用于球心进入/离开检测与日志，不产生碰撞或视觉。

## 路段唯一 ID
@export var segment_id: String = "seg_0"
## 路段类型（受控枚举字符串）
@export_enum(
	"start",
	"acceleration",
	"brake_approach",
	"left_turn",
	"right_turn",
	"recovery",
	"perturb_candidate",
	"choice_approach",
	"choice_branch"
) var segment_type: String = "start"
## 轴对齐矩形：左上角世界坐标
@export var rect_position: Vector2 = Vector2.ZERO
## 轴对齐矩形尺寸
@export var rect_size: Vector2 = Vector2(100.0, 100.0)

## 返回世界空间轴对齐矩形
func as_rect() -> Rect2:
	return Rect2(rect_position, rect_size)
