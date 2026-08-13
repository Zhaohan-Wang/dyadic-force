class_name GoalArea
extends Area2D
## 终点传送门：漩涡 shader 持续旋转；球靠近变亮加速，
## 球完全压上后充能（白热化），充满发出 reached。
## 传送演出（光柱 / 火花 / 全白）由 Level 通过 power_up()/spawn_beam() 驱动。

signal reached
signal ball_entered
signal ball_left

## 球压住门心后需要保持的充能时间（秒）
@export var hold_time: float = 0.6
## 传送门视觉半宽（像素）；高度会再乘 squash 压扁成椭圆
@export var portal_radius: float = 32.0
## Y 向压扁比例：制造俯视透视（椭圆门面）
@export var portal_squash: float = 0.55
## 开始产生亮度反馈的感应距离（像素）
@export var near_radius: float = 160.0
## 球心与门心距离小于此值视为"完全压上"
@export var lock_radius: float = 24.0

var _ball: PixelBall
var _mat: ShaderMaterial
var _hold: float = 0.0
var _armed: bool = true
## 演出接管后不再按距离更新 proximity/activation（由 power_up 推满）
var _performing: bool = false
## 当前接近度（供 _process 积分角速度，不直接乘 TIME）
var _proximity: float = 0.0
## 累加旋转相位 / 呼吸相位（与相机完全解耦）
var _spin: float = 0.0
var _pulse: float = 0.0
var _inside_lock: bool = false

func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	_build_visual()

## 注入球引用（Level 在建关时调用）
func set_ball(ball: PixelBall) -> void:
	_ball = ball

## 传送门视觉：地面贴花（z=-1）；X 按半径、Y 再压扁成椭圆透视。
## 贴图比可见圆更大（UV fit），外圈光环不会被 Sprite 四边裁掉。
func _build_visual() -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Vortex"
	var side: int = 64
	var img: Image = Image.create(side, side, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# fit=0.82：可见圆半径 = portal_radius，贴图半宽再放大 1/fit 留边
	const FIT: float = 0.82
	var sx: float = (portal_radius * 2.0 / float(side)) / FIT
	sprite.scale = Vector2(sx, sx * portal_squash)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/portal.gdshader")
	_mat.set_shader_parameter("fit", FIT)
	sprite.material = _mat
	# 父节点 GoalArea 已锁在 z=-1；漩涡相对父节点即可
	sprite.z_as_relative = true
	sprite.z_index = 0
	# 默认居中，视觉圆心 = GoalArea.global_position = LevelDef.goal_point
	sprite.centered = true
	add_child(sprite)

## 每帧按自身角速度积分相位——相机怎么动都不影响转速
func _process(delta: float) -> void:
	if _mat == null:
		return
	var act: float = 0.0
	if _performing:
		act = float(_mat.get_shader_parameter("activation"))
	else:
		act = (_hold / hold_time) * 0.6 if hold_time > 0.0 else 0.0
	# 基础转速 + 靠近加速 + 充能狂转；用积分而非 TIME*speed，改速度时相位连续
	var omega: float = 1.4 + _proximity * 2.2 + act * 6.0
	_spin += omega * delta
	_pulse += 3.0 * delta
	_mat.set_shader_parameter("spin", _spin)
	_mat.set_shader_parameter("pulse_phase", _pulse)

func _physics_process(delta: float) -> void:
	if _ball == null or _performing:
		return
	var dist: float = _ball.global_position.distance_to(global_position)
	_proximity = clampf(1.0 - dist / near_radius, 0.0, 1.0)
	var inside_now: bool = dist <= lock_radius
	if inside_now != _inside_lock:
		_inside_lock = inside_now
		if _inside_lock:
			ball_entered.emit()
		else:
			ball_left.emit()

	# 完全压上 → 充能；离开 → 快速泄能
	if _armed and inside_now:
		_hold = minf(hold_time, _hold + delta)
	else:
		_hold = maxf(0.0, _hold - delta * 2.5)

	_mat.set_shader_parameter("proximity", _proximity)
	_mat.set_shader_parameter("activation", _hold / hold_time * 0.6)

	if _armed and _hold >= hold_time:
		_armed = false
		reached.emit()

## 传送演出只让地面漩涡加速并变亮。
## 门本体始终保持 z=-1；前后景光效由独立 TeleportFx 绘制。
func power_up(duration: float) -> void:
	_performing = true
	_proximity = 1.0
	var tween: Tween = create_tween()
	tween.tween_method(
		func(v: float) -> void: _mat.set_shader_parameter("activation", v),
		0.55, 0.92, duration
	)
	_mat.set_shader_parameter("proximity", 1.0)
