class_name TeleportFxLayer
extends Node2D
## 传送演出的单个绘制层。
## 后层（front=false）：收束椭圆、细束托举，永远在球后。
## 前层（front=true）：轨道光点、离场闪点，只在关键帧压到角色前。

const COL_CYAN: Color = Color("78dce3")
const COL_BLUE: Color = Color("397ea6")
const COL_CREAM: Color = Color("fff4d6")

var front: bool = false
var progress: float = 0.0

## 更新归一化演出进度并重绘。
func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	if front:
		_draw_front()
	else:
		_draw_back()

## 后层：先让三道椭圆向门心收束，再从地面长出窄而分层的锥形光束。
func _draw_back() -> void:
	var gather: float = _ease_out(clampf(progress / 0.28, 0.0, 1.0))
	var lift: float = _smooth_range(progress, 0.20, 0.48)
	var release: float = _smooth_range(progress, 0.72, 1.0)

	# 三道地面椭圆向内收拢：负责“锁定位置”，不盖住角色。
	for i: int in 3:
		var start_radius: float = 58.0 + float(i) * 12.0
		var radius: float = lerpf(start_radius, 31.0 + float(i) * 2.0, gather)
		var alpha: float = (1.0 - gather * 0.72) * (0.22 - float(i) * 0.045)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.46))
		draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			48,
			Color(COL_CYAN, alpha),
			2.0
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 光束不使用矩形贴图：三层窄锥形从门口向上延伸，边缘天然收尖。
	if lift > 0.0:
		var top_y: float = lerpf(-18.0, -168.0, lift)
		var beam_alpha: float = lift * (1.0 - release)
		_draw_beam_wedge(top_y, 24.0, 8.0, Color(COL_BLUE, beam_alpha * 0.10))
		_draw_beam_wedge(top_y, 14.0, 5.0, Color(COL_CYAN, beam_alpha * 0.16))
		_draw_beam_wedge(top_y, 5.0, 2.0, Color(COL_CREAM, beam_alpha * 0.26))

	# 门心亮环保持在地面层，为上升提供明确的出发点。
	var floor_alpha: float = 0.28 + lift * 0.34 - release * 0.22
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.52))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 40, Color(COL_CREAM, floor_alpha), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 绘制一层上窄下宽的光束锥。
func _draw_beam_wedge(top_y: float, bottom_half: float, top_half: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(-bottom_half, 2.0),
		Vector2(-top_half, top_y),
		Vector2(top_half, top_y),
		Vector2(bottom_half, 2.0),
	])
	draw_colored_polygon(points, color)

## 前层：光点沿椭圆轨道收束；最后只用一个小闪点遮住角色消失帧。
func _draw_front() -> void:
	var gather: float = _ease_out(clampf(progress / 0.34, 0.0, 1.0))
	var lift: float = _smooth_range(progress, 0.26, 0.70)
	var release: float = _smooth_range(progress, 0.70, 1.0)

	# 八个规则分布的光点，避免随机粒子带来的散乱和廉价感。
	for i: int in 8:
		var phase: float = TAU * float(i) / 8.0 + progress * 5.0
		var orbit_x: float = lerpf(54.0, 29.0, gather)
		var orbit_y: float = lerpf(22.0, 11.0, gather)
		var rise_y: float = lerpf(0.0, -128.0, lift)
		var pos: Vector2 = Vector2(
			cos(phase) * orbit_x,
			sin(phase) * orbit_y + rise_y
		)
		var mote_alpha: float = (0.25 + gather * 0.55) * (1.0 - release)
		var mote_size: float = 2.0 if i % 2 == 0 else 1.5
		draw_rect(
			Rect2(pos - Vector2.ONE * mote_size, Vector2.ONE * mote_size * 2.0),
			Color(COL_CREAM if i % 3 == 0 else COL_CYAN, mote_alpha)
		)

	# 离场闪点：短、尖、面积小，只负责藏住最终消失帧。
	var glint: float = 1.0 - absf(progress - 0.82) / 0.10
	glint = clampf(glint, 0.0, 1.0)
	if glint > 0.0:
		var center: Vector2 = Vector2(0.0, -148.0)
		var arm: float = lerpf(5.0, 20.0, glint)
		draw_line(center - Vector2(arm, 0.0), center + Vector2(arm, 0.0), Color(COL_CREAM, glint), 2.0)
		draw_line(center - Vector2(0.0, arm), center + Vector2(0.0, arm), Color(COL_CREAM, glint), 2.0)
		draw_circle(center, 3.0 + glint * 2.0, Color(COL_CREAM, glint * 0.9))

## 三次平滑区间，用于无突变地开启阶段。
func _smooth_range(value: float, from: float, to: float) -> float:
	var t: float = clampf((value - from) / maxf(to - from, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## 三次缓出，让收束初段快、末段稳。
func _ease_out(value: float) -> float:
	return 1.0 - pow(1.0 - value, 3.0)
