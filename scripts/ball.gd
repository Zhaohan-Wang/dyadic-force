class_name PixelBall
extends RigidBody2D
## 像素风"伪 3D"滚动球（由两只轮缘上的猴子驱动）。
##
## 控制模型：每人在轮缘接触点施力（法向 + 切向投影），合力与真实力矩自然耦合。
##   - 两人同向 → 扭矩抵消、牵引效率高，易克服静摩擦起步；
##   - 两人失配 → 旋转上升、平移牵引下降（打滑）；
##   - 单人推 → 可修正方向，但通常无法独自稳定起步/高效搬运。
##
## 物理手感：
## - 静摩擦门槛：静止时团队合力须跨过阈值才启动；
## - 动摩擦更低，保留惯性；
## - 输入经短时建立/释放曲线，键盘也不会瞬间满推。

## 法向满推加速度（像素/秒²）；接触力 = 投影分量 × 加速度 × mass
@export var normal_accel: float = 150.0
## 切向满推加速度；满推时扭矩也按同一套接触力算，失配会明显打转
@export var tangent_accel: float = 145.0
## 静止时团队合力（加速度）须超过该阈值才启动
@export var static_friction: float = 145.0
## 运动中滚动摩擦减速度（像素/秒²）
@export var kinetic_friction: float = 30.0
## 低于该线速度视为静止（启动判定）
@export var rest_speed: float = 8.0
## 失配时平移牵引下限（0～1）；1 = 无惩罚
@export var traction_floor: float = 0.35
## 手柄输入建立时间（秒）
@export var input_rise_joy: float = 0.10
## 键盘/十字键输入建立时间（秒）
@export var input_rise_digital: float = 0.16
## 松手释放时间（秒）
@export var input_release: float = 0.08
## 闲置猴子脚下接触点的库仑摩擦（像素/秒²）
@export var idle_contact_friction: float = 28.0
## 闲置接触点的黏性阻尼系数（1/秒）
@export var idle_contact_drag: float = 0.50
## 低于该接触速度时逐渐撤掉库仑摩擦
@export var idle_contact_soft_speed: float = 12.0
## 闲置猴子抓紧响应速度（1/秒）
@export var idle_grip_engage: float = 0.7
## 重新操作后松开阻力的响应速度（1/秒）
@export var idle_grip_release: float = 12.0
## 两人都松手滑行时的乘员阻力倍率
@export var coasting_grip_factor: float = 0.05
## 球半径（像素），需与碰撞体半径一致；接触力臂用此值而非视觉锚点
@export var ball_radius: float = 44.0
## 球贴图边长（虚拟像素数）
@export var texture_size: int = 88
## 触发震屏/扣血的最小速度突变（像素/秒）
@export var impact_threshold: float = 90.0

## 兼容旧导出名：场景若仍写 push_force / friction_decel，映射到新参数
@export var push_force: float = 150.0:
	set(value):
		push_force = value
		normal_accel = value
@export var friction_decel: float = 30.0:
	set(value):
		friction_decel = value
		kinetic_friction = value
@export var spin_accel: float = 0.0

## 球撞到障碍/围墙时发出（参数 = 速度突变量）
signal impacted(strength: float)

## 球当前姿态（局部 -> 视图），随滚动/自转累积
var _orientation: Basis = Basis.IDENTITY
var _monkeys: Array[Monkey] = []
var _prev_velocity: Vector2 = Vector2.ZERO
var _idle_resistances: Array[float] = []
## 每槽滤波后的应用输入（世界方向 × 幅值 0～1）
var _applied_moves: Array[Vector2] = []
## 调试/测试可读的上一帧协作状态
var last_slip: float = 0.0
var last_traction: float = 1.0
var last_drive_accel: float = 0.0
var last_torque: float = 0.0
var last_started: bool = false

@onready var _sprite: Sprite2D = $BallSprite
@onready var _shadow: Sprite2D = $Shadow

func _ready() -> void:
	var img: Image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_sprite.texture = tex
	_shadow.texture = tex
	(_sprite.material as ShaderMaterial).set_shader_parameter("pixel_count", float(texture_size))
	(_shadow.material as ShaderMaterial).set_shader_parameter("pixel_count", float(texture_size))
	# 球体转动惯量 I = 0.4 m R²（比圆盘 0.5 更易转、更有失配感）
	inertia = 0.4 * mass * ball_radius * ball_radius
	for child: Node in get_children():
		if child is Monkey:
			_monkeys.append(child as Monkey)
			_idle_resistances.append(0.0)
			_applied_moves.append(Vector2.ZERO)
	_prev_velocity = linear_velocity
	_push_orientation_to_shader()

func _physics_process(delta: float) -> void:
	var active_count: int = 0
	var contact_forces: Array[Vector2] = []
	var contact_offsets: Array[Vector2] = []
	var force_mags: Array[float] = []

	for i: int in _monkeys.size():
		var sample: ForceMapper.Sample = InputHub.get_force_sample(_monkeys[i].player_slot)
		var target_move: Vector2 = sample.move
		var rise: float = (
			input_rise_digital
			if _slot_is_digital(_monkeys[i].player_slot)
			else input_rise_joy
		)
		_applied_moves[i] = _filter_move(_applied_moves[i], target_move, rise, input_release, delta)
		var move: Vector2 = _applied_moves[i]
		var idle: bool = move.length() < 0.02
		if not idle:
			active_count += 1
		_update_idle_resistance(i, idle, delta)

		# 用碰撞半径作为力臂；局部轮缘方向转到世界坐标后再投影世界输入
		var rim_local: Vector2 = _monkeys[i].position.normalized()
		if rim_local == Vector2.ZERO:
			rim_local = Vector2.UP if i == 0 else Vector2.DOWN
		var normal: Vector2 = rim_local.rotated(rotation)
		var tangent: Vector2 = Vector2(-normal.y, normal.x)
		var offset: Vector2 = normal * ball_radius
		var force: Vector2 = (
			normal * (move.dot(normal) * normal_accel * mass)
			+ tangent * (move.dot(tangent) * tangent_accel * mass)
		)
		contact_forces.append(force)
		contact_offsets.append(offset)
		force_mags.append(force.length())

	var net_force: Vector2 = Vector2.ZERO
	var torque: float = 0.0
	var force_sum: float = 0.0
	for i: int in contact_forces.size():
		net_force += contact_forces[i]
		torque += contact_offsets[i].cross(contact_forces[i])
		force_sum += force_mags[i]

	var slip: float = 0.0
	if force_sum > 0.001:
		slip = clampf(absf(torque) / (ball_radius * force_sum), 0.0, 1.0)
	var traction: float = lerpf(traction_floor, 1.0, 1.0 - slip)
	last_slip = slip
	last_traction = traction
	last_torque = torque

	var drive: Vector2 = net_force * traction
	var drive_accel: float = drive.length() / maxf(mass, 0.001)
	last_drive_accel = drive_accel

	var speed: float = linear_velocity.length()
	var at_rest: bool = speed <= rest_speed
	# 静摩擦：未跨过阈值时不给平移（扭矩仍可施加，便于原地拧/修方向）
	var can_translate: bool = (not at_rest) or drive_accel >= static_friction
	if not can_translate:
		drive = Vector2.ZERO
	last_started = can_translate and drive_accel >= static_friction

	if drive != Vector2.ZERO:
		apply_central_force(drive)
	if absf(torque) > 0.001:
		apply_torque(torque)

	# 未启动时跳过闲置接触：否则单人扭矩会经另一只猴子的抓地“拧”出平移
	if can_translate or not at_rest:
		_apply_idle_contact_forces(delta, active_count > 0)

	# 动摩擦：仅在可平移运动中
	speed = linear_velocity.length()
	if can_translate and speed > 0.0:
		var friction: float = kinetic_friction
		if drive == Vector2.ZERO and speed <= friction * delta:
			linear_velocity = Vector2.ZERO
			speed = 0.0
		else:
			apply_central_force(-linear_velocity / speed * friction * mass)

	if absf(torque) < 0.01 and absf(angular_velocity) < 0.05:
		angular_velocity = 0.0

	# 硬静摩擦：未达启动阈值时钉住线速度，避免数值噪声或接触反力蠕动
	speed = linear_velocity.length()
	if speed <= rest_speed and drive_accel < static_friction:
		linear_velocity = Vector2.ZERO
		speed = 0.0

	if speed > 1.0:
		var axis: Vector3 = Vector3(-linear_velocity.y, linear_velocity.x, 0.0).normalized()
		var angle: float = speed * delta / ball_radius
		_orientation = Basis(axis, angle) * _orientation
	if absf(angular_velocity) > 0.001:
		_orientation = Basis(Vector3(0.0, 0.0, 1.0), angular_velocity * delta) * _orientation
	_orientation = _orientation.orthonormalized()
	_push_orientation_to_shader()

	var impact: float = (_prev_velocity - linear_velocity).length()
	if impact >= impact_threshold:
		impacted.emit(impact)
	_prev_velocity = linear_velocity

func _slot_is_digital(slot: int) -> bool:
	var kind: InputHub.SourceKind = InputHub.slot_kind(slot)
	return (
		kind == InputHub.SourceKind.KEYBOARD_WASD
		or kind == InputHub.SourceKind.KEYBOARD_ARROWS
	)

## 对目标输入做上升/下降时间滤波；松手更快，按键建立更慢。
func _filter_move(
	current: Vector2,
	target: Vector2,
	rise_s: float,
	release_s: float,
	delta: float,
) -> Vector2:
	var cur_len: float = current.length()
	var tgt_len: float = target.length()
	var cur_dir: Vector2 = current / cur_len if cur_len > 0.001 else Vector2.ZERO
	var tgt_dir: Vector2 = target / tgt_len if tgt_len > 0.001 else cur_dir
	if tgt_dir == Vector2.ZERO and cur_dir == Vector2.ZERO:
		return Vector2.ZERO

	var tau: float = rise_s if tgt_len >= cur_len else release_s
	var alpha: float = 1.0 - exp(-delta / maxf(tau, 0.001))
	var next_len: float = lerpf(cur_len, tgt_len, alpha)
	var next_dir: Vector2 = cur_dir.lerp(tgt_dir, alpha)
	if next_dir.length() > 0.001:
		next_dir = next_dir.normalized()
	else:
		next_dir = tgt_dir
	if next_len < 0.001:
		return Vector2.ZERO
	return next_dir * next_len

func _update_idle_resistance(index: int, idle: bool, delta: float) -> void:
	var target: float = 1.0 if idle else 0.0
	var response: float = idle_grip_engage if idle else idle_grip_release
	_idle_resistances[index] = move_toward(
		_idle_resistances[index],
		target,
		response * delta
	)
	_monkeys[index].set_idle_resistance(_idle_resistances[index])

func _apply_idle_contact_forces(delta: float, partner_is_pushing: bool) -> void:
	for i: int in _monkeys.size():
		var grip: float = _idle_resistances[i]
		if not partner_is_pushing:
			grip *= coasting_grip_factor
		if grip <= 0.001:
			continue
		var rim_local: Vector2 = _monkeys[i].position.normalized()
		if rim_local == Vector2.ZERO:
			continue
		var offset: Vector2 = rim_local.rotated(rotation) * ball_radius
		var rotational_velocity: Vector2 = Vector2(-offset.y, offset.x) * angular_velocity
		var contact_velocity: Vector2 = linear_velocity + rotational_velocity
		var contact_speed: float = contact_velocity.length()
		if contact_speed <= 0.01:
			continue
		var contact_dir: Vector2 = contact_velocity / contact_speed
		var static_mix: float = clampf(
			contact_speed / maxf(idle_contact_soft_speed, 0.01),
			0.0,
			1.0
		)
		var desired_force: float = (
			idle_contact_friction * static_mix
			+ contact_speed * idle_contact_drag
		) * grip * mass
		var lever: float = offset.cross(contact_dir)
		var inverse_effective_mass: float = (
			1.0 / maxf(mass, 0.001)
			+ lever * lever / maxf(inertia, 0.001)
		)
		var effective_mass: float = 1.0 / inverse_effective_mass
		var max_stopping_force: float = contact_speed * effective_mass / maxf(delta, 0.001)
		var force_magnitude: float = minf(desired_force, max_stopping_force)
		apply_force(-contact_dir * force_magnitude, offset)

func _process(_delta: float) -> void:
	_sprite.rotation = -rotation
	_shadow.rotation = -rotation
	_shadow.position = Vector2(ball_radius * 0.16, ball_radius * 0.48).rotated(-rotation)

func _push_orientation_to_shader() -> void:
	var mat: ShaderMaterial = _sprite.material as ShaderMaterial
	mat.set_shader_parameter("ball_rot", _orientation)
