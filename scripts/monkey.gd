class_name Monkey
extends Node2D
## 站在球轮缘上的猴子角色（玩家实际控制的对象）。
##
## 设计要点：
## - 猴子自身不带任何物理：它是球（RigidBody2D）的子节点，
##   位置锁死在轮缘锚点上，球自转时被动跟着转；
## - 视觉与物理锚点分离：所有可见元素挂在 _visual 容器下，
##   远侧（球后方）的视觉锚点会向球心方向压缩，配合前后换层
##   实现"猴子转到球后面时被球挡住、只露出脑袋"的纵深感；
## - 脚下有一片与球影同一光源逻辑（正下方投影）的小椭圆阴影；
## - 动画三态：有输入播 run；没输入但球在动/在转时播 drag（被球拖着走，
##   用跳跃帧表现手脚张开的失衡感）；完全静止播 idle；
## - 头顶用像素字体显示 P1 / P2 标签（关闭抗锯齿保证锐利）；
## - 按方向键时在身旁弹出指向该方向的箭头（弹簧弹出动效）。

## 玩家槽位（0 = P1，1 = P2），输入统一走 InputHub
@export var player_slot: int = 0
## 兼容旧场景的动作前缀（仅在无 InputHub 时回退）
@export var action_prefix: String = "p1"
## 头顶显示的玩家标签
@export var display_name: String = "P1"
## 方向箭头在 UI 图集里的区域（默认取朝右的三角，运行时按方向旋转）
@export var arrow_region: Rect2 = Rect2(256, 0, 16, 16)
## 标签文字颜色（两名玩家用不同颜色便于区分）
@export var label_color: Color = Color(1.0, 0.98, 0.9)

## 箭头绕猴子身体中心的轨道半径（像素）；实际半径随力度 m2 在 [MIN, MAX] 间插值
const ARROW_ORBIT_MIN: float = 18.0
const ARROW_ORBIT_MAX: float = 30.0
## 箭头缩放随力度：轻推略小，满推略大
const ARROW_SCALE_MIN: float = 0.55
const ARROW_SCALE_MAX: float = 1.15
## 猴子身体中心相对脚底锚点的偏移（贴图 32x32，脚底对齐节点原点）
const BODY_CENTER: Vector2 = Vector2(0.0, -12.0)
## 整体视觉再往下压一点：默认正对（上下端点）时原先略偏高
const VISUAL_Y_BIAS: float = 3.0
## 远侧（球后方）视觉锚点的 y 压缩系数：把猴子往球心压，
## 让它的下半身沉到球的轮廓里，被球贴图挡住
const FAR_SIDE_SQUASH: float = 0.5
## 前后换层的滞回带（像素），避免在球侧面来回抖动
const BEHIND_SWITCH: float = 3.0
## 被拖着走的判定阈值：球线速度（像素/秒）或角速度（弧度/秒）
const DRAG_SPEED: float = 60.0
const DRAG_SPIN: float = 1.2

## 当前帧的输入方向（球通过 read_input() 取实时值；幅值 = m2·gain）
var input_vector: Vector2 = Vector2.ZERO
## 当前帧力度 0～1（ForceMapper.Sample.m2 × gain），驱动箭头远近/大小
var input_intensity: float = 0.0

var _behind: bool = false        # 当前是否处于球的后方（绘制在球贴图之下）
## 闲置系绳阻力权重（由 PixelBall 注入，0=自由 1=完全拖拽）
var _idle_resistance: float = 0.0
## 经过阻尼滤波的拖拽视觉偏移与倾角，隔离物理帧中的微小速度噪声
var _smoothed_drag_offset: Vector2 = Vector2.ZERO
var _smoothed_drag_lean: float = 0.0
var _visual: Node2D              # 视觉容器（阴影/动画/标签/箭头都挂在这里）
var _shadow: Sprite2D            # 脚下椭圆阴影
var _anim: AnimatedSprite2D      # 猴子动画
var _label: Sprite2D             # 头顶 P1/P2 标签（代码生成的微型像素位图）
var _arrow: Sprite2D             # 方向箭头
var _arrow_spring: Spring2D      # 驱动箭头缩放的弹簧（弹出/缩回动效）

var _idle_tex: Texture2D = preload("res://assets/characters/monkey_idle.png")
var _run_tex: Texture2D = preload("res://assets/characters/monkey_run.png")
var _jump_tex: Texture2D = preload("res://assets/characters/monkey_jump.png")
var _ui_tex: Texture2D = preload("res://assets/ui/ui_basic_sheet.png")
var _shadow_shader: Shader = preload("res://shaders/ball_shadow.gdshader")

@onready var _ball: RigidBody2D = get_parent() as RigidBody2D

func _ready() -> void:
	_visual = Node2D.new()
	add_child(_visual)
	# 构建顺序即绘制顺序：阴影最底、动画居中、标签和箭头在上
	_build_shadow()
	_build_animation()
	_build_label()
	_build_arrow()
	# 箭头缩放弹簧：短时长 + 一点回弹，弹出时有"啵"的手感
	_arrow_spring = Spring2D.new(0.35, 0.25)
	_arrow_spring.reset(Vector2.ZERO)

## 读取本玩家当前的方向输入（球的脚本每个物理帧调用）
func read_input() -> Vector2:
	# 统一走 InputHub（autoload）；未就绪时回退动作映射
	var hub: Node = get_node_or_null("/root/InputHub")
	if hub != null:
		var sample: ForceMapper.Sample = InputHub.get_force_sample(player_slot)
		input_intensity = sample.m2 * sample.gain
		return sample.move
	input_intensity = 0.0
	return Input.get_vector(
		action_prefix + "_left", action_prefix + "_right",
		action_prefix + "_up", action_prefix + "_down"
	)

## 球设置闲置阻力，用于把物理状态同步成可读的拖拽姿态。
func set_idle_resistance(value: float) -> void:
	_idle_resistance = clampf(value, 0.0, 1.0)

func _physics_process(_delta: float) -> void:
	input_vector = read_input()
	# —— 动画三态：主动跑 / 被球拖着走 / 待机 ——
	var ball_speed: float = _ball.linear_velocity.length()
	var ball_spin: float = absf(_ball.angular_velocity)
	if input_vector != Vector2.ZERO:
		if _anim.animation != &"run":
			_anim.play(&"run")
		if absf(input_vector.x) > 0.05:
			_anim.flip_h = input_vector.x < 0.0
	elif (
		ball_speed > DRAG_SPEED
		or ball_spin > DRAG_SPIN
		or (_idle_resistance > 0.15 and (ball_speed > 8.0 or ball_spin > 0.15))
	):
		if _anim.animation != &"drag":
			_anim.play(&"drag")
		if absf(_ball.linear_velocity.x) > 20.0:
			_anim.flip_h = _ball.linear_velocity.x < 0.0
	else:
		if _anim.animation != &"idle":
			_anim.play(&"idle")

func _process(delta: float) -> void:
	# —— 视觉锚点：远侧的猴子往球心方向压，制造 3/4 视角的纵深 ——
	var off: Vector2 = global_position - _ball.global_position
	var vis: Vector2 = off
	if off.y < 0.0:
		vis.y *= FAR_SIDE_SQUASH
	vis.y += VISUAL_Y_BIAS  # 正对端点时整体略下移，避免看起来飘在球沿上方

	# 先计算拖拽目标，再用指数阻尼过滤；低速符号翻转不会直接传到角色画面。
	var target_drag_offset: Vector2 = Vector2.ZERO
	var target_drag_lean: float = 0.0
	if _idle_resistance > 0.001 and _ball.linear_velocity.length() > 3.0:
		var trail_dir: Vector2 = -_ball.linear_velocity.normalized()
		target_drag_offset = trail_dir * 4.0 * _idle_resistance
		target_drag_lean = clampf(
			-_ball.linear_velocity.x / 180.0,
			-1.0,
			1.0
		) * 0.12 * _idle_resistance
	var visual_response: float = 1.0 - exp(-12.0 * delta)
	_smoothed_drag_offset = _smoothed_drag_offset.lerp(
		target_drag_offset,
		visual_response
	)
	_smoothed_drag_lean = lerpf(
		_smoothed_drag_lean,
		target_drag_lean,
		visual_response
	)
	vis += _smoothed_drag_offset
	_visual.global_position = _ball.global_position + vis
	_visual.global_rotation = _smoothed_drag_lean

	# —— 前后遮挡：远侧移到球贴图之前绘制，近侧移回最上层（带滞回）——
	# 球的子节点顺序：Shadow(0)、BallSprite(1)、猴子们、CollisionShape2D
	if not _behind and off.y < -BEHIND_SWITCH:
		_behind = true
		_ball.move_child(self, 1)  # 插到 BallSprite 之前 → 被球挡住
	elif _behind and off.y > BEHIND_SWITCH:
		_behind = false
		_ball.move_child(self, _ball.get_child_count() - 1)  # 移回最上层

	# —— 箭头：360° 方向 + 随力度变化的距离/缩放/透明度 ——
	if input_vector != Vector2.ZERO:
		var dir: Vector2 = input_vector.normalized()
		var intensity: float = clampf(input_intensity, 0.0, 1.0)
		var orbit: float = lerpf(ARROW_ORBIT_MIN, ARROW_ORBIT_MAX, intensity)
		var scale_target: float = lerpf(ARROW_SCALE_MIN, ARROW_SCALE_MAX, intensity)
		_arrow.visible = true
		_arrow.position = BODY_CENTER + dir * orbit
		_arrow.rotation = dir.angle()
		_arrow.modulate.a = lerpf(0.45, 1.0, intensity)
		_arrow_spring.target = Vector2.ONE * scale_target
	else:
		_arrow_spring.target = Vector2.ZERO
	var arrow_scale: Vector2 = _arrow_spring.update(delta)
	_arrow.scale = arrow_scale
	if input_vector == Vector2.ZERO and arrow_scale.length() < 0.06:
		_arrow.visible = false
		_arrow.modulate.a = 1.0

## 脚下椭圆阴影：与球同一光源（左上 → 影落右下），压扁贴地，不挡读路
func _build_shadow() -> void:
	_shadow = Sprite2D.new()
	_shadow.name = "MonkeyShadow"
	var img: Image = Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_shadow.texture = ImageTexture.create_from_image(img)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shadow_shader
	mat.set_shader_parameter("pixel_count", 20.0)
	mat.set_shader_parameter("shadow_color", Color(0.16, 0.15, 0.10, 0.28))
	_shadow.material = mat
	_shadow.scale = Vector2(1.05, 0.48)
	# 脚底略偏右下 = 光源在左上时的落点，避免影心压在角色正中显得飘
	_shadow.position = Vector2(2.0, 1.0)
	_visual.add_child(_shadow)

## 用三张精灵表（Idle 18 帧 / Run 8 帧 / Jump 4 帧，均为 32x32）构建动画
func _build_animation() -> void:
	_anim = AnimatedSprite2D.new()
	var frames: SpriteFrames = SpriteFrames.new()
	_add_strip(frames, &"idle", _idle_tex, 18, 10.0)
	_add_strip(frames, &"run", _run_tex, 8, 12.0)
	_add_strip(frames, &"drag", _jump_tex, 4, 8.0)  # 跳跃帧当"被拖着走"的失衡动画
	frames.remove_animation(&"default")
	_anim.sprite_frames = frames
	_anim.offset = BODY_CENTER  # 脚底对齐节点原点（球的轮缘锚点）
	_visual.add_child(_anim)
	_anim.frame_changed.connect(_on_animation_frame_changed)
	_anim.play(&"idle")

## 跑步循环每四帧落脚一次；AudioHub 还会按玩家槽位做节流和轻微变调。
func _on_animation_frame_changed() -> void:
	if (
		_anim.animation == &"run"
		and (_anim.frame == 1 or _anim.frame == 5)
		and input_vector != Vector2.ZERO
	):
		AudioHub.play_footstep(player_slot)

## 把一条横向精灵表注册为循环动画
func _add_strip(frames: SpriteFrames, anim_name: StringName, tex: Texture2D, count: int, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)
	for i: int in count:
		var frame: AtlasTexture = AtlasTexture.new()
		frame.atlas = tex
		frame.region = Rect2(float(i) * 32.0, 0.0, 32.0, 32.0)
		frames.add_frame(anim_name, frame)

## 头顶的 P1/P2 标签。
## 不用字体渲染：素材包的 TTF 设计尺寸是 14px，缩小必然丢笔画，
## 这里用 3x5 微型像素字形直接生成位图（字身 + 一圈深色描边），
## 尺寸只有字体方案的一半且逐像素锐利。
func _build_label() -> void:
	# 逐字符收集字形像素（画布留 1 像素描边边距）
	var pixels: Array[Vector2i] = []
	var cursor_x: int = 1
	for ci: int in display_name.length():
		var rows: PackedStringArray = _glyph_rows(display_name[ci])
		for y: int in rows.size():
			var row: String = rows[y]
			for x: int in row.length():
				if row[x] == "#":
					pixels.append(Vector2i(cursor_x + x, 1 + y))
		cursor_x += 4  # 字宽 3 + 字距 1

	var img: Image = Image.create(cursor_x, 7, false, Image.FORMAT_RGBA8)
	# 先铺 8 邻域描边，再画字身
	var outline_color: Color = Color(0.24, 0.16, 0.12)
	for p: Vector2i in pixels:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				img.set_pixel(p.x + dx, p.y + dy, outline_color)
	for p: Vector2i in pixels:
		img.set_pixelv(p, label_color)

	_label = Sprite2D.new()
	_label.texture = ImageTexture.create_from_image(img)
	_label.position = Vector2(0.0, -32.0)  # 悬在脑袋顶上方
	_visual.add_child(_label)

## 3x5 微型像素字形表（目前只需要 P / 1 / 2，需要时再补）
func _glyph_rows(ch: String) -> PackedStringArray:
	match ch:
		"P":
			return PackedStringArray(["##.", "#.#", "##.", "#..", "#.."])
		"1":
			return PackedStringArray([".#.", "##.", ".#.", ".#.", "###"])
		"2":
			return PackedStringArray(["###", "..#", "###", "#..", "###"])
	return PackedStringArray()

## 方向箭头（默认隐藏，按键时弹出）
func _build_arrow() -> void:
	_arrow = Sprite2D.new()
	_arrow.texture = _ui_tex
	_arrow.region_enabled = true
	_arrow.region_rect = arrow_region
	_arrow.visible = false
	_visual.add_child(_arrow)
