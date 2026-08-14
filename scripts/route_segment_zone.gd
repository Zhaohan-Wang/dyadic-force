class_name RouteSegmentZone
extends Area2D
## 不可见实验路段：仅检测球心进入/离开，不产生碰撞或视觉。

signal segment_entered(segment_id: String, segment_type: String)
signal segment_exited(segment_id: String, segment_type: String)

var def: SegmentDef
var _ball: PixelBall = null
var _inside: bool = false

func setup(segment_def: SegmentDef, ball: PixelBall) -> void:
	def = segment_def
	_ball = ball
	name = "RouteSegment_%s" % def.segment_id
	add_to_group("non_damaging_trigger")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	# 不挂 CollisionShape：用球心矩形检测，避免物理层干扰
	position = Vector2.ZERO

func _physics_process(_delta: float) -> void:
	if def == null or _ball == null:
		return
	var rect: Rect2 = def.as_rect()
	var now_inside: bool = rect.has_point(_ball.global_position)
	if now_inside and not _inside:
		_inside = true
		segment_entered.emit(def.segment_id, def.segment_type)
	elif not now_inside and _inside:
		_inside = false
		segment_exited.emit(def.segment_id, def.segment_type)

func contains_ball() -> bool:
	return _inside

func get_segment_id() -> String:
	return def.segment_id if def != null else ""

func get_segment_type() -> String:
	return def.segment_type if def != null else ""
