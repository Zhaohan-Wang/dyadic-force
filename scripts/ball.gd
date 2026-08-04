class_name PixelBall
extends RigidBody2D
## 像素风"伪 3D"滚动球（由两只轮缘上的猴子驱动）。
##
## 控制模型：玩家不再直接推球，而是各自控制一只锁在球轮缘上的猴子。
## 每只猴子的方向输入被视为"在它所站的轮缘点上发力"，分解成两部分：
##   - 平移分量：apply_central_force（方向 = 输入方向）；
##   - 旋转分量：锚点方向与输入方向的叉积 → apply_torque。
## 于是自然涌现出双人配合：
##   - 两人同向推 → 扭矩相互抵消，球纯平移；
##   - 两人反向推 → 推力相互抵消，球原地旋转（猴子沿轮缘转圈）；
##   - 单人推 → 又移又转，需要另一人配合修正。
##
## 物理手感：
## - 只施加力（不直接改速度），起步/停止都有明显的惯性；
## - 线性：恒定滚动摩擦 + 线性阻尼（限制最高速度）；
## - 角度：角阻尼（场景里配置）+ 低速吸附归零；
## - 视觉滚动：无滑动滚动（线速度）+ 绕视轴自转（角速度）一起积分姿态矩阵，
##   传给 shader；球贴图子节点每帧反向旋转，保证光照方向恒定、
##   自转完全由 shader 的球面纹理体现。

## 单人满推时的引擎加速度（像素/秒²）；物理力 = move × push_force × mass。
## move 已是实验虚拟力 / Fmax（0～1），这里不要再除一次 Fmax。
@export var push_force: float = 150.0
## 单只猴子全力切向发力时的角加速度（弧度/秒²）；同样按 move 幅值连续缩放
@export var spin_accel: float = 3.4
## 滚动摩擦产生的恒定减速度（像素/秒²）；须明显低于单人满推加速度
@export var friction_decel: float = 40.0
## 闲置猴子脚下接触点的库仑摩擦（像素/秒²）
@export var idle_contact_friction: float = 65.0
## 闲置接触点的黏性阻尼系数（1/秒）；速度越快拖力越强
@export var idle_contact_drag: float = 1.35
## 低于该接触速度时逐渐撤掉库仑摩擦，避免静止附近正负翻转
@export var idle_contact_soft_speed: float = 12.0
## 闲置猴子抓紧地面的响应速度（1/秒）
@export var idle_grip_engage: float = 1.0
## 重新操作后松开阻力的响应速度（1/秒）
@export var idle_grip_release: float = 12.0
## 两人都松手随惯性滑行时，只保留少量乘员接触阻力
@export var coasting_grip_factor: float = 0.08
## 球半径（像素），需与碰撞体半径一致
@export var ball_radius: float = 44.0
## 球贴图边长（虚拟像素数），决定像素颗粒粗细
@export var texture_size: int = 88
## 触发震屏/扣血的最小速度突变（像素/秒）
@export var impact_threshold: float = 90.0

## 球撞到障碍/围墙时发出（参数 = 速度突变量），供分屏相机震屏与扣血
signal impacted(strength: float)

## 球当前姿态（局部坐标 -> 视图坐标的旋转），随滚动/自转不断累积
var _orientation: Basis = Basis.IDENTITY
## 轮缘上的猴子列表（_ready 时从子节点收集）
var _monkeys: Array[Monkey] = []
## 上一物理帧线速度，用于检测碰撞冲击
var _prev_velocity: Vector2 = Vector2.ZERO
## 每只猴子当前脚下抓地权重（0～1），同时驱动物理与拖拽姿态
var _idle_resistances: Array[float] = []

@onready var _sprite: Sprite2D = $BallSprite
@onready var _shadow: Sprite2D = $Shadow

func _ready() -> void:
	# 运行时生成一张纯白贴图：它只用来确定绘制矩形的大小，
	# 实际颜色全部由 shader 逐像素计算，因此无需美术资源。
	var img: Image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_sprite.texture = tex
	_shadow.texture = tex
	# 把虚拟像素数同步给两个 shader，保证像素颗粒与贴图尺寸一致
	(_sprite.material as ShaderMaterial).set_shader_parameter("pixel_count", float(texture_size))
	(_shadow.material as ShaderMaterial).set_shader_parameter("pixel_count", float(texture_size))
	# 显式设置圆盘转动惯量（I = m·r²/2），让扭矩标定可预期
	inertia = 0.5 * mass * ball_radius * ball_radius
	# 收集轮缘上的猴子
	for child: Node in get_children():
		if child is Monkey:
			_monkeys.append(child as Monkey)
			_idle_resistances.append(0.0)
	_prev_velocity = linear_velocity
	_push_orientation_to_shader()

func _physics_process(delta: float) -> void:
	# —— 先收集力采样与脚下抓地状态（与实验映射同源，无二次阈值）——
	var moves: Array[Vector2] = []
	var active_count: int = 0
	for i: int in _monkeys.size():
		var sample: ForceMapper.Sample = InputHub.get_force_sample(_monkeys[i].player_slot)
		var move: Vector2 = sample.move
		if move != Vector2.ZERO:
			active_count += 1
		moves.append(move)
		_update_idle_resistance(i, move == Vector2.ZERO, delta)

	# —— 每只猴子的虚拟力 → 推力 + 扭矩 ——
	var total_input: Vector2 = Vector2.ZERO
	var total_torque_input: float = 0.0
	for i: int in _monkeys.size():
		var monkey: Monkey = _monkeys[i]
		var move: Vector2 = moves[i]
		if move == Vector2.ZERO:
			continue
		total_input += move
		# 平移分量：move 已是 force/Fmax（0～1），再乘 push_force 得到引擎加速度。
		apply_central_force(move * push_force * mass)
		# 旋转分量：叉积给出"切向发力"的比例与方向；幅值随 m2·gain 连续缩放
		var anchor_dir: Vector2 = (monkey.global_position - global_position).normalized()
		var torque_factor: float = anchor_dir.cross(move)
		total_torque_input += torque_factor
		apply_torque(torque_factor * spin_accel * inertia)

	# 有队友发力时，闲置猴子在轮缘接触点形成完整拖拽阻力；
	# 两人都松手时一起随球滑行，只保留少量乘员接触阻力。
	# apply_force(force, offset) 会自然同时影响平移和旋转，不需要隐藏倍率。
	_apply_idle_contact_forces(delta, active_count > 0)

	# —— 线性滚动摩擦：与速度方向相反的恒定减速度 ——
	var velocity: Vector2 = linear_velocity
	var speed: float = velocity.length()
	if speed > 0.0:
		if total_input == Vector2.ZERO and speed <= friction_decel * delta:
			# 速度低于本帧摩擦能消耗的量时直接归零，避免在零点附近来回抖动
			linear_velocity = Vector2.ZERO
		else:
			apply_central_force(-velocity / speed * friction_decel * mass)

	# —— 角速度低速吸附：角阻尼是指数衰减，最后一点靠吸附归零 ——
	if absf(total_torque_input) < 0.01 and absf(angular_velocity) < 0.08:
		angular_velocity = 0.0

	# —— 视觉姿态积分 ——
	# 1) 无滑动滚动：滚动轴 = 地面法线 × 速度方向，角度 = 位移 / 半径
	if speed > 1.0:
		var axis: Vector3 = Vector3(-velocity.y, velocity.x, 0.0).normalized()
		var angle: float = speed * delta / ball_radius
		_orientation = Basis(axis, angle) * _orientation
	# 2) 绕视轴自转：直接使用刚体角速度
	if absf(angular_velocity) > 0.001:
		_orientation = Basis(Vector3(0.0, 0.0, 1.0), angular_velocity * delta) * _orientation
	# 定期正交化，防止浮点误差累积导致矩阵变形
	_orientation = _orientation.orthonormalized()
	_push_orientation_to_shader()

	# —— 碰撞冲击检测（震屏 / 扣血；手柄震动改听 BallHealth.damaged）——
	var impact: float = (_prev_velocity - linear_velocity).length()
	if impact >= impact_threshold:
		impacted.emit(impact)
	_prev_velocity = linear_velocity

## 更新单只猴子的脚下抓地：松手后逐渐抓紧，重新操作时快速释放。
## 该权重同时显示为拖拽姿态，因此玩家能看到阻力来源。
func _update_idle_resistance(index: int, idle: bool, delta: float) -> void:
	var target: float = 1.0 if idle else 0.0
	var response: float = idle_grip_engage if idle else idle_grip_release
	_idle_resistances[index] = move_toward(
		_idle_resistances[index],
		target,
		response * delta
	)
	_monkeys[index].set_idle_resistance(_idle_resistances[index])

## 在每只闲置猴子的轮缘接触点计算点速度并施加反向摩擦。
## 接触点速度 = 球心线速度 + 角速度 × 半径；因此一股力自然阻碍平移与自转。
func _apply_idle_contact_forces(delta: float, partner_is_pushing: bool) -> void:
	for i: int in _monkeys.size():
		var grip: float = _idle_resistances[i]
		if not partner_is_pushing:
			grip *= coasting_grip_factor
		if grip <= 0.001:
			continue
		var offset: Vector2 = _monkeys[i].global_position - global_position
		var rotational_velocity: Vector2 = Vector2(-offset.y, offset.x) * angular_velocity
		var contact_velocity: Vector2 = linear_velocity + rotational_velocity
		var contact_speed: float = contact_velocity.length()
		if contact_speed <= 0.01:
			continue
		var normal: Vector2 = contact_velocity / contact_speed

		# 静止附近平滑撤掉恒定摩擦，只保留黏性阻尼。
		# 否则恒定摩擦会跨过零点，让角速度每帧正负翻转。
		var static_mix: float = clampf(
			contact_speed / maxf(idle_contact_soft_speed, 0.01),
			0.0,
			1.0
		)
		var desired_force: float = (
			idle_contact_friction * static_mix
			+ contact_speed * idle_contact_drag
		) * grip * mass

		# 接触点有效质量：
		# 1/m_eff = 1/m + (r×n)²/I。
		# 用它算“恰好把该方向点速度降到零”的最大力，防止过度修正造成抖动。
		var lever: float = offset.cross(normal)
		var inverse_effective_mass: float = (
			1.0 / maxf(mass, 0.001)
			+ lever * lever / maxf(inertia, 0.001)
		)
		var effective_mass: float = 1.0 / inverse_effective_mass
		var max_stopping_force: float = (
			contact_speed * effective_mass / maxf(delta, 0.001)
		)
		var force_magnitude: float = minf(desired_force, max_stopping_force)
		var contact_force: Vector2 = -normal * force_magnitude
		apply_force(contact_force, offset)

func _process(_delta: float) -> void:
	# 球贴图与阴影保持直立：自转的视觉效果完全交给 shader 的球面纹理，
	# 这样光照方向/投影位置不会跟着刚体转（光源应固定在世界里）。
	_sprite.rotation = -rotation
	_shadow.rotation = -rotation
	# 光源在左上（与球 shader light_dir 一致）→ 影落右下；
	# 略偏右下而不是正下方，读路时影不会糊在球心正南挡通道。
	_shadow.position = Vector2(ball_radius * 0.16, ball_radius * 0.48).rotated(-rotation)

## 把当前姿态矩阵传给球的 shader（mat3 uniform）
func _push_orientation_to_shader() -> void:
	var mat: ShaderMaterial = _sprite.material as ShaderMaterial
	mat.set_shader_parameter("ball_rot", _orientation)
