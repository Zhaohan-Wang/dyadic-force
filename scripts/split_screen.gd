class_name SplitScreen
extends CanvasLayer
## 左右分屏控制器。
##
## 左半屏 SubViewport 容纳整个游戏世界并跟随 P1；
## 右半屏共享同一 World2D，相机跟随 P2。
## HUD：轻量像素暗角、中缝侧影、无底角标字；球碰撞时两侧同步震屏。
##
## 由 Main 在世界搭建完毕后调用 activate()，避免围墙等节点漏挂。

## 单侧相机缩放（越大越聚焦）
@export var camera_zoom: float = 3.6
## 相机活动范围边距
@export var limit_margin: int = 64
## 岛屿尺寸（与 main.gd 保持一致，用于相机限位）
@export var island_w_px: int = 480
@export var island_h_px: int = 288

var _left_vp: SubViewport
var _right_vp: SubViewport
var _cam_p1: SpringCamera2D
var _cam_p2: SpringCamera2D
var _root: Control
var _active: bool = false

## 启动分屏：把世界节点挂进左视口，右视口共享世界，并创建双相机
func activate(world_nodes: Array[Node], monkey1: Node2D, monkey2: Node2D, ball: PixelBall) -> void:
	if _active:
		return
	_active = true
	_build_layout()
	for node: Node in world_nodes:
		node.reparent(_left_vp)
	_right_vp.world_2d = _left_vp.world_2d
	_build_cameras(monkey1, monkey2, ball)
	ball.impacted.connect(_on_ball_impacted)

## 构建左右 SubViewportContainer + 暗角 / 中缝 / 角标 HUD
func _build_layout() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var left_box: SubViewportContainer = _make_pane(true)
	var right_box: SubViewportContainer = _make_pane(false)
	_root.add_child(left_box)
	_root.add_child(right_box)

	_left_vp = _make_viewport(true)
	_right_vp = _make_viewport(false)
	left_box.add_child(_left_vp)
	right_box.add_child(_right_vp)

	# 每侧各自一层像素暗角（只压四角，很轻）；z 提到视口之上
	var vig_l: TextureRect = _make_vignette(true)
	var vig_r: TextureRect = _make_vignette(false)
	vig_l.z_index = 10
	vig_r.z_index = 10
	vig_l.visible = GameState.vignette_enabled
	vig_r.visible = GameState.vignette_enabled
	_root.add_child(vig_l)
	_root.add_child(vig_r)

	# 中缝两侧的像素阶梯侧影，让分割不那么生硬
	_root.add_child(_make_edge_fade(true))
	_root.add_child(_make_edge_fade(false))

	# 中缝主线 + 细高光
	_root.add_child(_make_divider(Color(0.12, 0.10, 0.08, 0.92), 2.0))
	_root.add_child(_make_divider(Color(0.95, 0.88, 0.65, 0.20), 1.0))

	# 全屏最外一圈极淡描边，收住画面
	_root.add_child(_make_outer_frame())

	# 用 UI 图集小面板做角标底，比纯色方块更像正式 HUD
	_add_corner_badge(true, "P1", Color(1.0, 0.98, 0.9))
	_add_corner_badge(false, "P2", Color(0.95, 0.78, 0.45))

## 创建半屏 SubViewportContainer
func _make_pane(is_left: bool) -> SubViewportContainer:
	var box: SubViewportContainer = SubViewportContainer.new()
	box.name = "LeftPane" if is_left else "RightPane"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_left:
		box.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		box.anchor_right = 0.5
		box.offset_right = -2.0
	else:
		box.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		box.anchor_left = 0.5
		box.offset_left = 2.0
	return box

## 创建游戏用 SubViewport（最近邻采样，保持像素风）
func _make_viewport(is_left: bool) -> SubViewport:
	var vp: SubViewport = SubViewport.new()
	vp.name = "LeftViewport" if is_left else "RightViewport"
	vp.transparent_bg = false
	vp.handle_input_locally = false
	vp.audio_listener_enable_2d = is_left
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	return vp

## 半屏像素暗角：低分辨率烘焙贴图 + 最近邻放大（阶梯渐变最稳）
func _make_vignette(is_left: bool) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = "VignetteL" if is_left else "VignetteR"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = _bake_vignette_texture(48, 64)
	if is_left:
		rect.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		rect.anchor_right = 0.5
		rect.offset_right = -2.0
	else:
		rect.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		rect.anchor_left = 0.5
		rect.offset_left = 2.0
	return rect

## 中缝侧影：烘焙横向阶梯渐变条
func _make_edge_fade(is_left: bool) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = "EdgeFadeL" if is_left else "EdgeFadeR"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = _bake_edge_fade_texture(16, 8, not is_left)
	rect.anchor_top = 0.0
	rect.anchor_bottom = 1.0
	rect.offset_top = 0.0
	rect.offset_bottom = 0.0
	if is_left:
		rect.anchor_left = 0.5
		rect.anchor_right = 0.5
		rect.offset_left = -36.0
		rect.offset_right = -2.0
	else:
		rect.anchor_left = 0.5
		rect.anchor_right = 0.5
		rect.offset_left = 2.0
		rect.offset_right = 36.0
	return rect

## 烘焙径向像素暗角（只压四角一小圈，强度也偏轻）
func _bake_vignette_texture(width: int, height: int) -> Texture2D:
	var img: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	# inner 越大 → 暗角越贴边；尽量只留四角一点点
	var inner: float = 1.05
	var outer: float = 1.42
	var steps: float = 3.0
	var intensity: float = 0.16
	var aspect: float = 1.15
	var dark: Color = Color(0.04, 0.03, 0.025, 1.0)
	for y: int in height:
		for x: int in width:
			var u: float = (float(x) + 0.5) / float(width)
			var v: float = (float(y) + 0.5) / float(height)
			var px: float = (u * 2.0 - 1.0) * aspect
			var py: float = v * 2.0 - 1.0
			var dist: float = sqrt(px * px + py * py)
			var t: float = clampf((dist - inner) / (outer - inner), 0.0, 1.0)
			t = floor(t * steps + 0.001) / steps
			var a: float = t * intensity
			img.set_pixel(x, y, Color(dark.r, dark.g, dark.b, a))
	return ImageTexture.create_from_image(img)

## 烘焙横向像素侧影（朝分割线一侧加深）
func _bake_edge_fade_texture(width: int, height: int, flip_x: bool) -> Texture2D:
	var img: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var steps: float = 3.0
	var intensity: float = 0.08
	var dark: Color = Color(0.05, 0.04, 0.03, 1.0)
	for y: int in height:
		for x: int in width:
			var u: float = (float(x) + 0.5) / float(width)
			if flip_x:
				u = 1.0 - u
			var t: float = floor(u * steps + 0.001) / steps
			img.set_pixel(x, y, Color(dark.r, dark.g, dark.b, t * intensity))
	return ImageTexture.create_from_image(img)

## 竖直分割线（居中，给定半宽）
func _make_divider(color: Color, half_width: float) -> ColorRect:
	var divider: ColorRect = ColorRect.new()
	divider.color = color
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.set_anchors_preset(Control.PRESET_CENTER)
	divider.anchor_top = 0.0
	divider.anchor_bottom = 1.0
	divider.offset_left = -half_width
	divider.offset_right = half_width
	divider.offset_top = 0.0
	divider.offset_bottom = 0.0
	return divider

## 全屏最外一圈 2px 描边，把画面"框"住
func _make_outer_frame() -> Control:
	var frame: Control = Control.new()
	frame.name = "OuterFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thickness: float = 3.0
	var color: Color = Color(0.10, 0.08, 0.06, 0.55)
	frame.add_child(_make_frame_bar(color, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, thickness)) # 上
	frame.add_child(_make_frame_bar(color, 0.0, 1.0, 1.0, 1.0, 0.0, -thickness, 0.0, 0.0)) # 下
	frame.add_child(_make_frame_bar(color, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, thickness, 0.0)) # 左
	frame.add_child(_make_frame_bar(color, 1.0, 0.0, 1.0, 1.0, -thickness, 0.0, 0.0, 0.0)) # 右
	return frame

## 外框单条 ColorRect
func _make_frame_bar(
	color: Color,
	al: float, at: float, ar: float, ab: float,
	ol: float, ot: float, oright: float, ob: float
) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = al
	bar.anchor_top = at
	bar.anchor_right = ar
	bar.anchor_bottom = ab
	bar.offset_left = ol
	bar.offset_top = ot
	bar.offset_right = oright
	bar.offset_bottom = ob
	return bar

## 两侧弹簧相机：左跟 P1，右跟 P2
func _build_cameras(monkey1: Node2D, monkey2: Node2D, ball: PixelBall) -> void:
	_cam_p1 = _make_camera("CameraP1", monkey1, ball)
	_cam_p2 = _make_camera("CameraP2", monkey2, ball)
	_left_vp.add_child(_cam_p1)
	_right_vp.add_child(_cam_p2)
	_cam_p1.make_current()
	_cam_p2.make_current()

## 创建并配置一台弹簧相机
func _make_camera(cam_name: String, target: Node2D, ball: PixelBall) -> SpringCamera2D:
	var cam: SpringCamera2D = SpringCamera2D.new()
	cam.name = cam_name
	cam.zoom = Vector2(camera_zoom, camera_zoom)
	cam.position_smoothing_enabled = false
	cam.configure(target, ball)
	cam.global_position = target.global_position
	_apply_limits(cam)
	return cam

## 相机活动范围：岛屿外扩一圈
func _apply_limits(cam: Camera2D) -> void:
	cam.limit_left = -limit_margin
	cam.limit_top = -limit_margin
	cam.limit_right = island_w_px + limit_margin
	cam.limit_bottom = island_h_px + limit_margin
	cam.limit_smoothed = true

## 球碰撞冲击 → 两侧相机同步震屏（可被设置关闭）
func _on_ball_impacted(strength: float) -> void:
	if not GameState.shake_enabled:
		return
	if _cam_p1 == null or _cam_p2 == null:
		return
	var shake: float = clampf(strength * 0.045, 1.5, 9.0)
	_cam_p1.add_shake(shake)
	_cam_p2.add_shake(shake)

## 外部按需触发震屏（例如扣血反馈）
func shake(strength: float) -> void:
	_on_ball_impacted(strength)

## 角落玩家角标：只有像素字，不加背景面板
func _add_corner_badge(is_left: bool, text: String, fill: Color) -> void:
	var label: TextureRect = TextureRect.new()
	label.texture = _make_label_texture(text, fill)
	label.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	label.stretch_mode = TextureRect.STRETCH_KEEP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.scale = Vector2(3.0, 3.0)
	var tex_w: float = float(label.texture.get_width())
	if is_left:
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.position = Vector2(18.0, 16.0)
	else:
		label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		label.position = Vector2(-18.0 - tex_w * 3.0, 16.0)
	_root.add_child(label)

## 生成角标文字位图（透明底 + 描边字）
func _make_label_texture(text: String, fill: Color) -> Texture2D:
	var glyphs: Dictionary = {
		"P": PackedStringArray(["##.", "#.#", "##.", "#..", "#.."]),
		"1": PackedStringArray([".#.", "##.", ".#.", ".#.", "###"]),
		"2": PackedStringArray(["###", "..#", "###", "#..", "###"]),
	}
	var pixels: Array[Vector2i] = []
	var cursor_x: int = 1
	for i: int in text.length():
		var ch: String = text[i]
		var rows: PackedStringArray = PackedStringArray()
		if glyphs.has(ch):
			rows = glyphs[ch] as PackedStringArray
		for y: int in rows.size():
			var row: String = rows[y]
			for x: int in row.length():
				if row[x] == "#":
					pixels.append(Vector2i(cursor_x + x, 1 + y))
		cursor_x += 4
	var w: int = cursor_x
	var h: int = 7
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var outline: Color = Color(0.22, 0.16, 0.12)
	for p: Vector2i in pixels:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var px: int = p.x + dx
				var py: int = p.y + dy
				if px >= 0 and py >= 0 and px < w and py < h:
					img.set_pixel(px, py, outline)
	for p: Vector2i in pixels:
		img.set_pixelv(p, fill)
	return ImageTexture.create_from_image(img)
