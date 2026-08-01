class_name UiSpring
extends Node
## UI 弹簧动效驱动器：把 Spring2D 挂到任意 Control 上，
## 以中心为锚点驱动 scale，实现弹入、聚焦放大、受击抖动等效果。
##
## 用法：
##   var spring: UiSpring = UiSpring.attach(button)
##   spring.pop_in(0.1)          # 延迟 0.1s 弹入
##   spring.set_scale_target(1.06)  # 聚焦放大
##   spring.punch(0.18)          # 瞬时冲量（如受击/就绪提示）

## 被驱动的控件
var _target: Control
## 缩放弹簧（x/y 同步）
var _spring: Spring2D
## 弹入前是否隐藏（pop_in 用）
var _pending_pop: bool = false

## 创建并挂载到控件；duration/bounce 与 Spring2D 语义一致
static func attach(target: Control, duration: float = 0.45, bounce: float = 0.25) -> UiSpring:
	var inst: UiSpring = UiSpring.new()
	inst._target = target
	inst._spring = Spring2D.new(duration, bounce)
	inst._spring.reset(Vector2.ONE)
	target.add_child(inst)
	return inst

func _process(delta: float) -> void:
	if _target == null:
		return
	# 锚点保持在控件中心，缩放才不会向右下偏移
	_target.pivot_offset = _target.size * 0.5
	_target.scale = _spring.update(delta)

## 从小到大弹入（带延迟），配合透明度渐入
func pop_in(delay: float = 0.0, from_scale: float = 0.4) -> void:
	_pending_pop = true
	_spring.reset(Vector2.ONE * from_scale)
	_spring.target = Vector2.ONE * from_scale
	_target.scale = _spring.position
	_target.modulate.a = 0.0
	# 节点可能尚未进树（比如构建中的卡片），用主循环的 SceneTree 起定时器
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var timer: SceneTreeTimer = tree.create_timer(delay)
	timer.timeout.connect(_do_pop)

func _do_pop() -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		return
	_pending_pop = false
	_spring.target = Vector2.ONE
	var tween: Tween = _target.create_tween()
	tween.tween_property(_target, "modulate:a", 1.0, 0.18)

## 设定持续追踪的缩放目标（聚焦 / 失焦）
func set_scale_target(target_scale: float) -> void:
	if _pending_pop:
		return
	_spring.target = Vector2.ONE * target_scale

## 给弹簧一个瞬时速度冲量，产生"duang"的一下
func punch(amount: float = 0.35) -> void:
	_spring.velocity += Vector2.ONE * amount * 6.0
