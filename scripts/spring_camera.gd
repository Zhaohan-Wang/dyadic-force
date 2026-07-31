class_name SpringCamera2D
extends Camera2D
## 弹簧跟随摄像机。
##
## 相机位置不直接绑定目标，而是用一根 duration/bounce 参数化的二维弹簧
## 去追踪"焦点"；焦点 = 目标位置 + 速度前瞻偏移。
## 分屏模式下两台相机各自跟随一只猴子；前瞻速度取自球的刚体速度，
## 碰撞震屏由球的冲击信号驱动，两台相机同步抖动。
##
## 注意：分屏右视口共享 World2D，但不能用 NodePath 跨视口 get_node，
## 因此目标引用通过 configure() 注入。

## 弹簧感知时长（秒），越大跟随越松弛
@export var duration: float = 0.55
## 弹跳系数：0 临界阻尼无回弹，>0 有回弹
@export var bounce: float = 0.15
## 速度前瞻时间（秒）
@export var look_ahead_time: float = 0.28
## 前瞻偏移上限（像素）
@export var max_look_ahead: float = 72.0
## 震屏衰减速度（强度/秒）
@export var shake_decay: float = 28.0
## 震屏最大位移（像素）
@export var shake_max_offset: float = 10.0

var _spring: Spring2D
var _target: Node2D
var _velocity_source: RigidBody2D
var _shake_strength: float = 0.0
var _configured: bool = false

## 注入跟随目标与速度来源（须在 add_child 之前调用）
func configure(target: Node2D, velocity_source: RigidBody2D) -> void:
	_target = target
	_velocity_source = velocity_source
	_configured = true

## 叠加一次碰撞震屏
func add_shake(strength: float) -> void:
	_shake_strength = minf(shake_max_offset, maxf(_shake_strength, strength))

func _ready() -> void:
	if not _configured:
		push_error("SpringCamera2D: 请先调用 configure()")
		return
	_spring = Spring2D.new(duration, bounce)
	_spring.reset(_target.global_position)
	global_position = _spring.position

func _physics_process(delta: float) -> void:
	if _spring == null or _target == null:
		return
	var vel: Vector2 = Vector2.ZERO
	if _velocity_source != null:
		vel = _velocity_source.linear_velocity
	var ahead: Vector2 = (vel * look_ahead_time).limit_length(max_look_ahead)
	_spring.target = _target.global_position + ahead
	var base: Vector2 = _spring.update(delta)

	# 震屏：强度衰减，位移每帧随机
	_shake_strength = move_toward(_shake_strength, 0.0, shake_decay * delta)
	var shake: Vector2 = Vector2.ZERO
	if _shake_strength > 0.05:
		shake = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * _shake_strength

	global_position = base + shake
