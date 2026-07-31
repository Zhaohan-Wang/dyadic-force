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

## 单只猴子推力产生的加速度（像素/秒²）
@export var push_force: float = 220.0
## 单只猴子全力切向发力时的角加速度（弧度/秒²）
@export var spin_accel: float = 4.5
## 滚动摩擦产生的恒定减速度（像素/秒²）
@export var friction_decel: float = 40.0
## 球半径（像素），需与碰撞体半径一致
@export var ball_radius: float = 44.0
## 球贴图边长（虚拟像素数），决定像素颗粒粗细
@export var texture_size: int = 88
## 触发震屏的最小速度突变（像素/秒）
@export var impact_threshold: float = 90.0

## 球撞到障碍/围墙时发出（参数 = 速度突变量），供分屏相机震屏
signal impacted(strength: float)

## 球当前姿态（局部坐标 -> 视图坐标的旋转），随滚动/自转不断累积
var _orientation: Basis = Basis.IDENTITY
## 轮缘上的猴子列表（_ready 时从子节点收集）
var _monkeys: Array[Monkey] = []
## 上一物理帧线速度，用于检测碰撞冲击
var _prev_velocity: Vector2 = Vector2.ZERO

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
	_prev_velocity = linear_velocity
	_push_orientation_to_shader()

func _physics_process(delta: float) -> void:
	# —— 猴子发力：每只猴子的输入 → 推力 + 扭矩 ——
	var total_input: Vector2 = Vector2.ZERO
	var total_torque_input: float = 0.0
	for monkey: Monkey in _monkeys:
		var dir: Vector2 = monkey.read_input()
		if dir == Vector2.ZERO:
			continue
		total_input += dir
		# 平移分量
		apply_central_force(dir * push_force * mass)
		# 旋转分量：叉积给出"切向发力"的比例与方向
		var anchor_dir: Vector2 = (monkey.global_position - global_position).normalized()
		var torque_factor: float = anchor_dir.cross(dir)
		total_torque_input += torque_factor
		apply_torque(torque_factor * spin_accel * inertia)

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

	# —— 碰撞冲击检测：速度突变超过阈值 → 通知相机震屏 ——
	var impact: float = (_prev_velocity - linear_velocity).length()
	if impact >= impact_threshold:
		impacted.emit(impact)
	_prev_velocity = linear_velocity

func _process(_delta: float) -> void:
	# 球贴图与阴影保持直立：自转的视觉效果完全交给 shader 的球面纹理，
	# 这样光照方向/投影位置不会跟着刚体转（光源应固定在世界里）。
	_sprite.rotation = -rotation
	_shadow.rotation = -rotation
	# 阴影偏移随半径略放大，保持与球同一光源逻辑（正下方投影）
	_shadow.position = Vector2(0.0, ball_radius * 0.5).rotated(-rotation)

## 把当前姿态矩阵传给球的 shader（mat3 uniform）
func _push_orientation_to_shader() -> void:
	var mat: ShaderMaterial = _sprite.material as ShaderMaterial
	mat.set_shader_parameter("ball_rot", _orientation)
