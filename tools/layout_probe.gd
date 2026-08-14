extends RefCounted
## 离线布局探针：直接用 WorldBuilder 造一遍关卡，再做球心可达性 BFS 与真实美术预览。
## 不加载 level.tscn，也不引用任何依赖 autoload 的脚本，所以能在 --script 模式下跑。
## 门一律视为"已打开"：探针不生成门体，走廊本身必须连通。

## 球半径（球心可行域按此内缩）
const BALL_RADIUS: float = 44.0
## BFS 网格步长（像素）
const CELL: float = 8.0

## 岛屿像素尺寸
var island_px: Vector2i = Vector2i.ZERO
## BFS 网格尺寸
var grid_w: int = 0
var grid_h: int = 0
## 1 = 球心不可站立
var blocked: PackedByteArray = PackedByteArray()
## 1 = 从出生点可达
var reach: PackedByteArray = PackedByteArray()
## 生成出来的世界根（含四层）
var world_root: Node2D = null
var water_layer: TileMapLayer = null
var ground_layer: TileMapLayer = null
var decor_layer: TileMapLayer = null
var world: Node2D = null

var _tex_cache: Dictionary[String, Image] = {}

## 造世界 + 算可达域。parent 必须已在场景树里（供 global_position 生效）。
func build(def: LevelDef, parent: Node) -> void:
	island_px = Vector2i(def.island_size.x * 16, def.island_size.y * 16)
	world_root = Node2D.new()
	water_layer = TileMapLayer.new()
	ground_layer = TileMapLayer.new()
	decor_layer = TileMapLayer.new()
	world = Node2D.new()
	world.y_sort_enabled = true
	world_root.add_child(water_layer)
	world_root.add_child(ground_layer)
	world_root.add_child(decor_layer)
	world_root.add_child(world)
	parent.add_child(world_root)

	var builder: WorldBuilder = WorldBuilder.new()
	builder.bind(water_layer, ground_layer, decor_layer, world)
	builder.build(def)

	_compute_blocked()
	_compute_reach(def.spawn_point)

## 把所有静态碰撞体刷成"球心禁区"网格
func _compute_blocked() -> void:
	grid_w = int(ceil(float(island_px.x) / CELL))
	grid_h = int(ceil(float(island_px.y) / CELL))
	blocked = PackedByteArray()
	blocked.resize(grid_w * grid_h)
	var shapes: Array[Dictionary] = []
	_collect_shapes(world, shapes)
	for shape: Dictionary in shapes:
		if str(shape["kind"]) == "circle":
			var center: Vector2 = shape["pos"] as Vector2
			var radius: float = float(shape["r"])
			_stamp_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), center, radius)
		else:
			_stamp_rect(shape["rect"] as Rect2, Vector2.ZERO, -1.0)

## 把矩形（radius >= 0 时按圆）刷进 blocked
func _stamp_rect(bounds: Rect2, center: Vector2, radius: float) -> void:
	var x0: int = clampi(int(floor(bounds.position.x / CELL)), 0, grid_w - 1)
	var x1: int = clampi(int(ceil(bounds.end.x / CELL)), 0, grid_w - 1)
	var y0: int = clampi(int(floor(bounds.position.y / CELL)), 0, grid_h - 1)
	var y1: int = clampi(int(ceil(bounds.end.y / CELL)), 0, grid_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var p: Vector2 = Vector2((float(ix) + 0.5) * CELL, (float(iy) + 0.5) * CELL)
			if radius >= 0.0:
				if p.distance_to(center) > radius:
					continue
			elif not bounds.has_point(p):
				continue
			blocked[iy * grid_w + ix] = 1

## 收集静态碰撞形状（半径已加上球半径，矩形已外扩球半径）
func _collect_shapes(node: Node, out: Array[Dictionary]) -> void:
	var body: StaticBody2D = node as StaticBody2D
	if body != null:
		for child: Node in body.get_children():
			var cs: CollisionShape2D = child as CollisionShape2D
			if cs == null or cs.disabled or cs.shape == null:
				continue
			var circle: CircleShape2D = cs.shape as CircleShape2D
			if circle != null:
				out.append({
					"kind": "circle",
					"pos": body.global_position + cs.position,
					"r": circle.radius + BALL_RADIUS,
				})
				continue
			var box: RectangleShape2D = cs.shape as RectangleShape2D
			if box != null:
				var center: Vector2 = body.global_position + cs.position
				out.append({
					"kind": "aabb",
					"rect": Rect2(center - box.size * 0.5, box.size).grow(BALL_RADIUS),
				})
	for child2: Node in node.get_children():
		_collect_shapes(child2, out)

## 从出生点做四邻 BFS
func _compute_reach(spawn: Vector2) -> void:
	reach = PackedByteArray()
	reach.resize(grid_w * grid_h)
	var start: Vector2i = _to_cell(spawn)
	if not _cell_ok(start.x, start.y):
		return
	var queue: PackedInt32Array = PackedInt32Array([start.y * grid_w + start.x])
	reach[start.y * grid_w + start.x] = 1
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var ix: int = idx % grid_w
		var iy: int = idx / grid_w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var jx: int = ix + d.x
			var jy: int = iy + d.y
			if not _cell_ok(jx, jy):
				continue
			var jdx: int = jy * grid_w + jx
			if reach[jdx] == 1:
				continue
			reach[jdx] = 1
			queue.append(jdx)

func _cell_ok(ix: int, iy: int) -> bool:
	if ix < 0 or iy < 0 or ix >= grid_w or iy >= grid_h:
		return false
	return blocked[iy * grid_w + ix] == 0

func _to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL)), int(floor(pos.y / CELL)))

## 球心能否站在该点
func is_free(pos: Vector2) -> bool:
	var c: Vector2i = _to_cell(pos)
	return _cell_ok(c.x, c.y)

## 该点是否从出生点可达
func is_reachable(pos: Vector2) -> bool:
	var c: Vector2i = _to_cell(pos)
	if c.x < 0 or c.y < 0 or c.x >= grid_w or c.y >= grid_h:
		return false
	return reach[c.y * grid_w + c.x] == 1

## 附近是否有可达格（容忍中心线离墙略近）
func reachable_near(pos: Vector2, cells: int) -> bool:
	for dy: int in range(-cells, cells + 1):
		for dx: int in range(-cells, cells + 1):
			if is_reachable(pos + Vector2(float(dx) * CELL, float(dy) * CELL)):
				return true
	return false

## 可达格总数（用于比较不同版本的可玩面积）
func reachable_cells() -> int:
	var count: int = 0
	for v: int in reach:
		count += v
	return count

# ---------- 真实美术预览 ----------

## 取素材图（tools 直接从文件读，避免压缩纹理取图差异）
func _image_for(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var path: String = texture.resource_path
	if path.is_empty():
		var generated: Image = texture.get_image()
		if generated != null and generated.get_format() != Image.FORMAT_RGBA8:
			generated.convert(Image.FORMAT_RGBA8)
		return generated
	if _tex_cache.has(path):
		return _tex_cache[path]
	var img: Image = Image.load_from_file(path)
	if img == null:
		img = texture.get_image()
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_tex_cache[path] = img
	return img

## 渲染整关真实画面（水面 + 地面 + 装饰 + 全部贴图），返回 RGBA8 图像
func render_art() -> Image:
	var canvas: Image = Image.create(island_px.x, island_px.y, false, Image.FORMAT_RGBA8)
	var water: Image = Image.load_from_file("res://assets/tiles/water.png")
	water.convert(Image.FORMAT_RGBA8)
	var water_tile: Rect2i = Rect2i(0, 0, 16, 16)
	for ty: int in range(0, island_px.y / 16 + 1):
		for tx: int in range(0, island_px.x / 16 + 1):
			canvas.blit_rect(water, water_tile, Vector2i(tx * 16, ty * 16))
	_blit_tilemap(canvas, ground_layer)
	_blit_tilemap(canvas, decor_layer)
	_blit_sprites(canvas, world)
	return canvas

func _blit_tilemap(canvas: Image, layer: TileMapLayer) -> void:
	if layer.tile_set == null:
		return
	var source: TileSetAtlasSource = layer.tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return
	var atlas: Image = _image_for(source.texture)
	if atlas == null:
		return
	for cell: Vector2i in layer.get_used_cells():
		var coords: Vector2i = layer.get_cell_atlas_coords(cell)
		if coords.x < 0:
			continue
		var src: Rect2i = Rect2i(coords * 16, Vector2i(16, 16))
		canvas.blend_rect(atlas, src, cell * 16)

func _blit_sprites(canvas: Image, node: Node) -> void:
	var sprite: Sprite2D = node as Sprite2D
	if sprite != null and sprite.texture != null:
		var img: Image = _image_for(sprite.texture)
		if img != null:
			var src: Rect2i = Rect2i(Vector2i.ZERO, img.get_size())
			if sprite.region_enabled:
				src = Rect2i(sprite.region_rect)
			var angle: float = sprite.global_rotation
			# offset 在 sprite 局部空间，会跟着节点一起转
			var center: Vector2 = sprite.global_position + sprite.offset.rotated(angle)
			if absf(angle) < 0.0001:
				canvas.blend_rect(img, src, Vector2i((center - Vector2(src.size) * 0.5).round()))
			else:
				_blend_rotated(canvas, img, src, center, angle)
	for child: Node in node.get_children():
		_blit_sprites(canvas, child)

## 旋转贴图（最近邻反向采样）。引导箭头会跟着行进方向转，
## 不处理旋转的话预览图里所有箭头都朝右，会误判成"方向标错了"。
func _blend_rotated(
	canvas: Image, img: Image, src: Rect2i, center: Vector2, angle: float
) -> void:
	var half: Vector2 = Vector2(src.size) * 0.5
	var radius: int = int(ceil(half.length())) + 1
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var dst: Vector2i = Vector2i(int(center.x) + dx, int(center.y) + dy)
			if dst.x < 0 or dst.y < 0 or dst.x >= canvas.get_width() or dst.y >= canvas.get_height():
				continue
			var local: Vector2 = (Vector2(dst) + Vector2(0.5, 0.5) - center).rotated(-angle) + half
			var sx: int = int(floor(local.x))
			var sy: int = int(floor(local.y))
			if sx < 0 or sy < 0 or sx >= src.size.x or sy >= src.size.y:
				continue
			var col: Color = img.get_pixel(src.position.x + sx, src.position.y + sy)
			if col.a <= 0.004:
				continue
			var base: Color = canvas.get_pixel(dst.x, dst.y)
			canvas.set_pixel(dst.x, dst.y, base.lerp(Color(col, 1.0), col.a))

## 在图上画线（调试图用）
func draw_line_on(img: Image, a: Vector2, b: Vector2, color: Color, thickness: int = 2) -> void:
	var steps: int = maxi(2, int(a.distance_to(b) / 2.0))
	for i: int in range(steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		for oy: int in range(-thickness, thickness + 1):
			for ox: int in range(-thickness, thickness + 1):
				var x: int = int(p.x) + ox
				var y: int = int(p.y) + oy
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				img.set_pixel(x, y, color)

## 在图上画矩形框
func draw_rect_on(img: Image, rect: Rect2, color: Color) -> void:
	draw_line_on(img, rect.position, Vector2(rect.end.x, rect.position.y), color, 1)
	draw_line_on(img, Vector2(rect.end.x, rect.position.y), rect.end, color, 1)
	draw_line_on(img, rect.end, Vector2(rect.position.x, rect.end.y), color, 1)
	draw_line_on(img, Vector2(rect.position.x, rect.end.y), rect.position, color, 1)

## 把不可达区域压暗，直观看出封死范围
func shade_unreachable(img: Image) -> void:
	for iy: int in grid_h:
		for ix: int in grid_w:
			if reach[iy * grid_w + ix] == 1:
				continue
			var px: int = int((float(ix) + 0.5) * CELL)
			var py: int = int((float(iy) + 0.5) * CELL)
			if px >= img.get_width() or py >= img.get_height():
				continue
			img.set_pixel(px, py, Color(0.85, 0.1, 0.1, 1.0))
