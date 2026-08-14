class_name GateBurst
extends Node2D
## 撞门粒子：成功撞开用大块木屑+闪光，失败撞击用少量尘土火花。
## 视觉语言对齐 BallBurst（像素碎片 / 冲击波），配色改成木质。

## 木屑颜色
const WOOD_COLORS: Array[Color] = [
	Color("8b5a2b"),
	Color("c4a381"),
	Color("5c3a1a"),
	Color("d4b483"),
	Color("7a4a22"),
]
## 撞击火花
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
	var gravity: float = 280.0
	var drag: float = 0.985
	var fade_pow: float = 1.6

var _parts: Array[Particle] = []
var _age: float = 0.0
var _life: float = 0.55
var _tex_dot: Texture2D
var _tex_shard: Texture2D
## Pixel Adventure 尘土粒子（带透明底）
var _tex_dust: Texture2D = preload("res://assets/topdown/dust.png")
var _flash: Sprite2D
var _ring: Sprite2D
var _is_break: bool = false

func _ready() -> void:
	_tex_dot = _make_rect_tex(2, 2)
	_tex_shard = _make_rect_tex(6, 3)
	z_index = 35
	if _is_break:
		_life = 0.70
		_spawn_flash()
		_spawn_ring()
		_spawn_shards(18)
		_spawn_dust(16)
		_spawn_sparks(12)
	else:
		_life = 0.38
		_spawn_dust(8)
		_spawn_sparks(6)

## 中心暖白闪光（仅撞开）
func _spawn_flash() -> void:
	_flash = Sprite2D.new()
	_flash.texture = _make_circle_tex(20, true)
	_flash.modulate = Color(1.0, 0.94, 0.78, 0.92)
	_flash.scale = Vector2.ONE * 0.4
	_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_flash)

## 冲击波环（仅撞开）
func _spawn_ring() -> void:
	_ring = Sprite2D.new()
	_ring.texture = _make_circle_tex(20, false)
	_ring.modulate = Color(0.95, 0.82, 0.55, 0.85)
	_ring.scale = Vector2.ONE * 0.6
	_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ring)

func _spawn_shards(count: int) -> void:
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + randf_range(-0.2, 0.2)
		var spr: Sprite2D = _make_sprite(
			_tex_shard,
			WOOD_COLORS[i % WOOD_COLORS.size()],
			Vector2(randf_range(1.2, 2.2), randf_range(0.9, 1.6))
		)
		_add_part(
			spr,
			Vector2.from_angle(angle) * randf_range(140.0, 340.0),
			randf_range(-14.0, 14.0),
			randf_range(260.0, 420.0),
			0.982,
			1.4
		)

func _spawn_dust(count: int) -> void:
	for i: int in count:
		var angle: float = randf() * TAU
		var color: Color = WOOD_COLORS[i % WOOD_COLORS.size()].lightened(0.22)
		color.a = 0.85
		var spr: Sprite2D = _make_sprite(
			_tex_dust,
			color,
			Vector2.ONE * randf_range(0.55, 1.15)
		)
		_add_part(
			spr,
			Vector2.from_angle(angle) * randf_range(40.0, 150.0),
			randf_range(-5.0, 5.0),
			randf_range(80.0, 180.0),
			0.96,
			2.0
		)

func _spawn_sparks(count: int) -> void:
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + randf_range(-0.12, 0.12)
		var spr: Sprite2D = _make_sprite(
			_tex_dot,
			SPARK_COLORS[i % SPARK_COLORS.size()],
			Vector2.ONE * randf_range(0.6, 1.0)
		)
		_add_part(
			spr,
			Vector2.from_angle(angle) * randf_range(180.0, 360.0),
			0.0,
			30.0,
			0.93,
			2.8
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
	var t: float = clampf(_age / _life, 0.0, 1.0)
	if _flash != null:
		var ft: float = clampf(_age / 0.18, 0.0, 1.0)
		_flash.scale = Vector2.ONE * lerpf(0.4, 2.6, 1.0 - pow(1.0 - ft, 3.0))
		_flash.modulate.a = 0.92 * (1.0 - ft * ft)
		if ft >= 1.0:
			_flash.queue_free()
			_flash = null
	if _ring != null:
		var rt: float = clampf(_age / 0.36, 0.0, 1.0)
		_ring.scale = Vector2.ONE * lerpf(0.6, 4.2, 1.0 - pow(1.0 - rt, 2.0))
		_ring.modulate.a = 0.85 * (1.0 - rt)
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
		p.node.scale = p.base_scale * lerpf(1.0, 0.4, t)
	if _age >= _life:
		queue_free()

func _make_sprite(tex: Texture2D, color: Color, scale: Vector2) -> Sprite2D:
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	spr.modulate = color
	spr.scale = scale
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
	return spr

func _make_rect_tex(w: int, h: int) -> Texture2D:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

func _make_circle_tex(diameter: int, filled: bool) -> Texture2D:
	var img: Image = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c: float = float(diameter) * 0.5 - 0.5
	var r: float = float(diameter) * 0.5 - 0.5
	for y: int in diameter:
		for x: int in diameter:
			var d: float = Vector2(float(x) - c, float(y) - c).length()
			var inside: bool = d <= r if filled else (d <= r and d >= r - 2.5)
			if inside:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## 撞开大门：木屑 + 闪光 + 冲击波
static func play_break(parent: Node, world_pos: Vector2) -> GateBurst:
	var burst: GateBurst = GateBurst.new()
	burst._is_break = true
	burst.name = "GateBurstBreak"
	parent.add_child(burst)
	burst.global_position = world_pos
	return burst

## 失败撞击：少量尘土火花
static func play_hit(parent: Node, world_pos: Vector2) -> GateBurst:
	var burst: GateBurst = GateBurst.new()
	burst._is_break = false
	burst.name = "GateBurstHit"
	parent.add_child(burst)
	burst.global_position = world_pos
	return burst
