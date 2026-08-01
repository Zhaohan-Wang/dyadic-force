class_name BallBurst
extends Node2D
## 球被撞烂时的爆炸：圆形白闪 + 冲击波环 + 大块碎片 + 细尘火花。
## 参考经典像素游戏爆炸（Celeste 死亡 / 塞尔达炸弹）：
## 中心是"圆形"闪光（非方块）快速膨胀消退，外圈冲击波环扩散，
## 碎片大而快，配合关卡层的顿帧与重震屏形成冲击感。

## 主碎片数量（大色块）
const SHARD_COUNT: int = 26
## 细尘数量
const DUST_COUNT: int = 34
## 火花环数量
const SPARK_COUNT: int = 20
## 总寿命（秒）
const LIFE: float = 0.9
## 中心闪光寿命（秒）
const FLASH_LIFE: float = 0.22
## 冲击波环寿命（秒）
const RING_LIFE: float = 0.45

## 球配色（实体碎片）
const SHARD_COLORS: Array[Color] = [
	Color("f2e5bc"),
	Color("79ab4c"),
	Color("de8b73"),
	Color("926a4c"),
	Color("c4a381"),
]
## 亮火花色
const SPARK_COLORS: Array[Color] = [
	Color("fff6d8"),
	Color("ffe08a"),
	Color("f2e5bc"),
]

## 单个粒子状态
class Particle:
	var node: Sprite2D
	var vel: Vector2 = Vector2.ZERO
	var spin: float = 0.0
	var base_scale: Vector2 = Vector2.ONE
	var start_alpha: float = 1.0
	var gravity: float = 380.0
	var drag: float = 0.985
	var fade_pow: float = 1.6

var _parts: Array[Particle] = []
var _age: float = 0.0
var _tex_dot: Texture2D
var _tex_shard: Texture2D
var _flash: Sprite2D
var _ring: Sprite2D

func _ready() -> void:
	_tex_dot = _make_rect_tex(2, 2)
	_tex_shard = _make_rect_tex(6, 3)
	z_index = 40
	_spawn_flash()
	_spawn_ring()
	_spawn_shards()
	_spawn_dust()
	_spawn_sparks()

## 中心圆形白闪：快速膨胀 + 极速淡出（圆形贴图，不再是大方块）
func _spawn_flash() -> void:
	_flash = Sprite2D.new()
	_flash.texture = _make_circle_tex(24, true)
	_flash.modulate = Color(1.0, 0.98, 0.9, 0.95)
	_flash.scale = Vector2.ONE * 0.5
	_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_flash)

## 冲击波环：空心像素圆环向外扩散淡出
func _spawn_ring() -> void:
	_ring = Sprite2D.new()
	_ring.texture = _make_circle_tex(24, false)
	_ring.modulate = Color(1.0, 0.93, 0.72, 0.9)
	_ring.scale = Vector2.ONE * 0.8
	_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ring)

## 大块碎片：更大更快，飞得更远
func _spawn_shards() -> void:
	for i: int in SHARD_COUNT:
		var angle: float = TAU * float(i) / float(SHARD_COUNT) + randf_range(-0.22, 0.22)
		var use_bar: bool = randf() > 0.3
		var spr: Sprite2D = _make_sprite(
			_tex_shard if use_bar else _tex_dot,
			SHARD_COLORS[i % SHARD_COLORS.size()],
			Vector2(randf_range(1.4, 2.6), randf_range(1.1, 2.2))
		)
		_add_part(
			spr,
			Vector2.from_angle(angle) * randf_range(160.0, 420.0),
			randf_range(-18.0, 18.0),
			randf_range(320.0, 520.0),
			0.984,
			1.5
		)

## 细尘：填中心与轨迹之间的空隙
func _spawn_dust() -> void:
	for i: int in DUST_COUNT:
		var angle: float = randf() * TAU
		var color: Color = SHARD_COLORS[i % SHARD_COLORS.size()].lightened(randf_range(0.0, 0.2))
		var spr: Sprite2D = _make_sprite(_tex_dot, color, Vector2.ONE * randf_range(0.6, 1.2))
		_add_part(
			spr,
			Vector2.from_angle(angle) * randf_range(30.0, 160.0),
			randf_range(-6.0, 6.0),
			randf_range(90.0, 200.0),
			0.96,
			2.2
		)

## 亮火花：一圈快速外扩的高亮点
func _spawn_sparks() -> void:
	for i: int in SPARK_COUNT:
		var angle: float = TAU * float(i) / float(SPARK_COUNT) + randf_range(-0.1, 0.1)
		var spr: Sprite2D = _make_sprite(
			_tex_dot,
			SPARK_COLORS[i % SPARK_COLORS.size()],
			Vector2.ONE * randf_range(0.7, 1.1)
		)
		spr.modulate.a = 0.95
		_add_part(
			spr,
			Vector2.from_angle(angle) * randf_range(260.0, 460.0),
			0.0,
			40.0,
			0.93,
			3.0
		)

func _add_part(
	spr: Sprite2D,
	vel: Vector2,
	spin: float,
	gravity: float,
	drag: float,
	fade_pow: float
) -> void:
	var p: Particle = Particle.new()
	p.node = spr
	p.vel = vel
	p.spin = spin
	p.base_scale = spr.scale
	p.start_alpha = spr.modulate.a
	p.gravity = gravity
	p.drag = drag
	p.fade_pow = fade_pow
	_parts.append(p)

func _process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / LIFE, 0.0, 1.0)

	# 中心闪光：0.22s 内从 0.5x 弹到 3.2x 并淡出
	if _flash != null:
		var ft: float = clampf(_age / FLASH_LIFE, 0.0, 1.0)
		_flash.scale = Vector2.ONE * lerpf(0.5, 3.2, 1.0 - pow(1.0 - ft, 3.0))
		_flash.modulate.a = 0.95 * (1.0 - ft * ft)
		if ft >= 1.0:
			_flash.queue_free()
			_flash = null

	# 冲击波环：0.45s 扩散到 5x 并淡出
	if _ring != null:
		var rt: float = clampf(_age / RING_LIFE, 0.0, 1.0)
		_ring.scale = Vector2.ONE * lerpf(0.8, 5.0, 1.0 - pow(1.0 - rt, 2.0))
		_ring.modulate.a = 0.9 * (1.0 - rt)
		if rt >= 1.0:
			_ring.queue_free()
			_ring = null

	for p: Particle in _parts:
		p.vel += Vector2(0.0, p.gravity) * delta
		p.vel *= p.drag
		p.node.position += p.vel * delta
		p.node.rotation += p.spin * delta
		var fade: float = pow(t, p.fade_pow)
		p.node.modulate.a = p.start_alpha * (1.0 - fade)
		p.node.scale = p.base_scale * lerpf(1.0, 0.35, t)

	if _age >= LIFE:
		queue_free()

func _make_sprite(tex: Texture2D, color: Color, scale: Vector2) -> Sprite2D:
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	spr.modulate = color
	spr.scale = scale
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
	return spr

## 烘焙实心矩形像素贴图
func _make_rect_tex(w: int, h: int) -> Texture2D:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

## 烘焙像素圆：filled=true 实心圆盘，false 空心圆环（3px 壁厚）
func _make_circle_tex(diameter: int, filled: bool) -> Texture2D:
	var img: Image = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c: float = float(diameter) * 0.5 - 0.5
	var r: float = float(diameter) * 0.5 - 0.5
	for y: int in diameter:
		for x: int in diameter:
			var d: float = Vector2(float(x) - c, float(y) - c).length()
			var inside: bool = d <= r if filled else (d <= r and d >= r - 3.0)
			if inside:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## 工厂：在父节点下于世界坐标处播放爆炸
static func play(parent: Node, world_pos: Vector2) -> BallBurst:
	var burst: BallBurst = BallBurst.new()
	burst.name = "BallBurst"
	parent.add_child(burst)
	burst.global_position = world_pos
	return burst
