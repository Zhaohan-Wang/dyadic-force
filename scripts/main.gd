extends Node2D
## 主场景搭建脚本。
##
## 运行时用 Sprout Lands 素材在代码里拼出一座被水环绕的草地小岛：
## - WaterLayer：铺满视野的 4 帧动画水面；
## - GroundLayer：用 3x3 圆角岛屿瓦片拼出的草地；
## - DecorLayer：随机撒的草丛贴片（永远画在球的下方，不参与遮挡）；
## - World（Y 排序）：成片的障碍物（树丛、石阵、灌木墙、木栅栏）+ 玩家的球，
##   所有障碍物都带碰撞体，球撞上会被挡住/弹开；
## - 四周生成隐形围墙，把球挡在岛内。

const TILE_SIZE: int = 16            # 素材瓦片尺寸（像素）
const ISLAND_W: int = 30             # 小岛宽度（瓦片数）
const ISLAND_H: int = 18             # 小岛高度（瓦片数）
const WATER_MARGIN: int = 12         # 水面向四周额外延伸的瓦片数
const SCATTER_SEED: int = 20260801   # 固定随机种子，保证每次运行布局一致
const SOURCE_ID: int = 0             # TileSet 图集源 ID（每个 TileSet 只有一个源）

## 草地装饰贴片在 grass.png 图集里的坐标（只保留草丛斑块，画在地面层，
## 位于球的下方，不会出现"花草浮在球上"的错误遮挡）
const DECOR_TILES: Array[Vector2i] = [
	Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5),
	Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
]

## 障碍物定义：图集像素区域 + 碰撞圆半径
class PropDef:
	var region: Rect2   # 在 grass_biome_things.png 里的像素区域
	var radius: float   # 碰撞圆半径

	func _init(p_region: Rect2, p_radius: float) -> void:
		region = p_region
		radius = p_radius

var _grass_tex: Texture2D = preload("res://assets/tiles/grass.png")
var _water_tex: Texture2D = preload("res://assets/tiles/water.png")
var _things_tex: Texture2D = preload("res://assets/objects/grass_biome_things.png")
var _fence_tex: Texture2D = preload("res://assets/tiles/fences.png")

@onready var _water_layer: TileMapLayer = $WaterLayer
@onready var _ground_layer: TileMapLayer = $GroundLayer
@onready var _decor_layer: TileMapLayer = $DecorLayer
@onready var _world: Node2D = $World
@onready var _ball: PixelBall = $World/Ball
@onready var _split_screen: SplitScreen = $SplitScreen

func _ready() -> void:
	_setup_water()
	_setup_ground_and_decor()
	_spawn_obstacles()
	_build_walls()
	# 世界就绪后再启动分屏：左跟 P1、右跟 P2，共享同一 World2D
	var world_nodes: Array[Node] = [_water_layer, _ground_layer, _decor_layer, _world]
	_split_screen.activate(
		world_nodes,
		_ball.get_node("Monkey1") as Node2D,
		_ball.get_node("Monkey2") as Node2D,
		_ball
	)

## 铺水面：单个动画瓦片（水贴图横向 4 帧）填满整个可见范围
func _setup_water() -> void:
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = _water_tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(Vector2i.ZERO)
	source.set_tile_animation_frames_count(Vector2i.ZERO, 4)
	for i: int in 4:
		source.set_tile_animation_frame_duration(Vector2i.ZERO, i, 0.4)

	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, SOURCE_ID)
	_water_layer.tile_set = tile_set

	for x: int in range(-WATER_MARGIN, ISLAND_W + WATER_MARGIN):
		for y: int in range(-WATER_MARGIN, ISLAND_H + WATER_MARGIN):
			_water_layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i.ZERO)

## 拼岛屿草地 + 随机撒草丛装饰贴片
func _setup_ground_and_decor() -> void:
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = _grass_tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	# 图集左上角的 3x3 圆角岛屿块：四角 + 四边 + 中心
	for ax: int in 3:
		for ay: int in 3:
			source.create_tile(Vector2i(ax, ay))
	for coords: Vector2i in DECOR_TILES:
		source.create_tile(coords)

	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, SOURCE_ID)
	_ground_layer.tile_set = tile_set
	_decor_layer.tile_set = tile_set

	# 根据格子在岛屿里的位置选择对应的边角/中心瓦片
	for x: int in ISLAND_W:
		for y: int in ISLAND_H:
			var ax: int = 0 if x == 0 else (2 if x == ISLAND_W - 1 else 1)
			var ay: int = 0 if y == 0 else (2 if y == ISLAND_H - 1 else 1)
			_ground_layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i(ax, ay))

	# 在岛屿内部稀疏地撒草丛贴片（地面纹理，帮助感知球的移动）
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	for x: int in range(1, ISLAND_W - 1):
		for y: int in range(1, ISLAND_H - 1):
			if rng.randf() < 0.09:
				var pick: Vector2i = DECOR_TILES[rng.randi_range(0, DECOR_TILES.size() - 1)]
				_decor_layer.set_cell(Vector2i(x, y), SOURCE_ID, pick)

# ============================================================
# 障碍物生成：成片的树丛 / 石阵 / 灌木墙 / 木栅栏 + 少量零散障碍
# ============================================================

## 树类障碍（大树 / 苹果树 / 小树）。
## 碰撞半径故意取得比树干大：球半径约 38，
## 半径太小会让球在视觉上"啃进"树冠里。
func _tree_defs() -> Array[PropDef]:
	var defs: Array[PropDef] = []
	defs.append(PropDef.new(Rect2(16, 0, 32, 32), 12.0))
	defs.append(PropDef.new(Rect2(48, 0, 32, 32), 12.0))
	defs.append(PropDef.new(Rect2(0, 0, 16, 32), 8.0))
	return defs

## 石头类障碍（大石 / 小石）
func _rock_defs() -> Array[PropDef]:
	var defs: Array[PropDef] = []
	defs.append(PropDef.new(Rect2(128, 16, 16, 16), 7.5))
	defs.append(PropDef.new(Rect2(112, 16, 16, 16), 6.5))
	return defs

## 灌木类障碍（莓果灌木 / 圆灌木）
func _bush_defs() -> Array[PropDef]:
	var defs: Array[PropDef] = []
	defs.append(PropDef.new(Rect2(0, 48, 16, 16), 8.5))
	defs.append(PropDef.new(Rect2(16, 48, 16, 16), 8.5))
	return defs

## 生成全部障碍物
func _spawn_obstacles() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED + 1
	var placed: Array[Vector2] = []
	var spawn: Vector2 = Vector2(ISLAND_W, ISLAND_H) * float(TILE_SIZE) * 0.5

	# 木栅栏墙：固定位置的两道横向障碍墙
	# （素材里没有纵向连接件，竖排会断开，所以栅栏只做横向；
	#   纵向的屏障由竖排的灌木墙承担）
	_spawn_fence_line(Vector2(160.0, 96.0), 6, placed)
	_spawn_fence_line(Vector2(264.0, 208.0), 5, placed)

	# 树丛与石阵：围绕随机锚点成片生成
	for i: int in 2:
		_spawn_cluster(rng, placed, spawn, _tree_defs(), 5, 40.0)
	for i: int in 2:
		_spawn_cluster(rng, placed, spawn, _rock_defs(), 5, 24.0)

	# 灌木墙：一横一竖两道，竖排承担纵向屏障
	_spawn_bush_wall(rng, placed, spawn, true)
	_spawn_bush_wall(rng, placed, spawn, false)

	# 少量零散的树和石头，填补空旷区域
	for i: int in 3:
		_place_random(rng, placed, spawn, _tree_defs())
	for i: int in 3:
		_place_random(rng, placed, spawn, _rock_defs())

## 围绕一个随机锚点成片生成障碍物（树丛 / 石阵）
func _spawn_cluster(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	spawn: Vector2,
	variants: Array[PropDef],
	member_count: int,
	cluster_radius: float
) -> void:
	# 锚点之间保持较大间距，保证簇与簇之间留有可通行的走廊
	var anchor: Vector2 = _find_spot(rng, placed, spawn, 64.0, 130.0, 96.0)
	if anchor == Vector2.INF:
		return
	for i: int in member_count:
		for attempt: int in 20:
			var offset: Vector2 = Vector2(
				rng.randf_range(-cluster_radius, cluster_radius),
				rng.randf_range(-cluster_radius, cluster_radius)
			)
			var pos: Vector2 = anchor + offset
			if not _is_inside_island(pos, 28.0):
				continue
			if pos.distance_to(spawn) < 90.0:
				continue
			if _too_close(placed, pos, 18.0):
				continue
			placed.append(pos)
			var def: PropDef = variants[rng.randi_range(0, variants.size() - 1)]
			_world.add_child(_make_prop(def, pos))
			break

## 生成一排紧挨的灌木，形成一道软性障碍墙
func _spawn_bush_wall(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	spawn: Vector2,
	horizontal: bool
) -> void:
	var bushes: Array[PropDef] = _bush_defs()
	var spacing: float = 13.0  # 灌木间距略小于贴图宽度，视觉上连成一排
	for attempt: int in 30:
		var count: int = rng.randi_range(4, 6)
		var dir: Vector2 = Vector2.RIGHT if horizontal else Vector2.DOWN
		var start: Vector2 = Vector2(
			rng.randf_range(48.0, float(ISLAND_W * TILE_SIZE) - 48.0),
			rng.randf_range(48.0, float(ISLAND_H * TILE_SIZE) - 48.0)
		)
		# 校验整排的每个位置都合法
		var ok: bool = true
		for i: int in count:
			var pos: Vector2 = start + dir * spacing * float(i)
			if not _is_inside_island(pos, 28.0) \
					or pos.distance_to(spawn) < 90.0 \
					or _too_close(placed, pos, 20.0):
				ok = false
				break
		if not ok:
			continue
		# 校验通过，整排放置（两种灌木交替，更自然）
		for i: int in count:
			var pos: Vector2 = start + dir * spacing * float(i)
			placed.append(pos)
			_world.add_child(_make_prop(bushes[i % bushes.size()], pos))
		return

## 生成一段横向木栅栏墙；每节栅栏独立成体（保证 Y 排序遮挡正确）
func _spawn_fence_line(start: Vector2, segments: int, placed: Array[Vector2]) -> void:
	for i: int in segments:
		var pos: Vector2 = start + Vector2(16.0 * float(i), 0.0)
		var body: StaticBody2D = StaticBody2D.new()
		body.position = pos

		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _fence_tex
		sprite.region_enabled = true
		# 图集第 3 行是纯横向栅栏：左端 / 中段 / 右端
		var col: int = 1 if i == 0 else (3 if i == segments - 1 else 2)
		sprite.region_rect = Rect2(float(col) * 16.0, 48.0, 16.0, 16.0)
		sprite.offset = Vector2(0.0, -8.0)  # 原点落在贴图底部
		body.add_child(sprite)

		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(16.0, 9.0)
		shape.shape = box
		shape.position = Vector2(0.0, -5.0)
		body.add_child(shape)

		placed.append(pos)
		_world.add_child(body)

## 放置单个零散障碍物
func _place_random(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	spawn: Vector2,
	variants: Array[PropDef]
) -> void:
	var pos: Vector2 = _find_spot(rng, placed, spawn, 32.0, 100.0, 34.0)
	if pos == Vector2.INF:
		return
	placed.append(pos)
	var def: PropDef = variants[rng.randi_range(0, variants.size() - 1)]
	_world.add_child(_make_prop(def, pos))

## 用拒绝采样在岛内找一个满足间距约束的落点；失败返回 Vector2.INF
func _find_spot(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	spawn: Vector2,
	margin: float,
	spawn_clear: float,
	spacing: float
) -> Vector2:
	for attempt: int in 60:
		var pos: Vector2 = Vector2(
			rng.randf_range(margin, float(ISLAND_W * TILE_SIZE) - margin),
			rng.randf_range(margin, float(ISLAND_H * TILE_SIZE) - margin)
		)
		if pos.distance_to(spawn) < spawn_clear:
			continue
		if _too_close(placed, pos, spacing):
			continue
		return pos
	return Vector2.INF

## 判断位置是否在岛屿内部（带边距）
func _is_inside_island(pos: Vector2, margin: float) -> bool:
	return pos.x >= margin and pos.x <= float(ISLAND_W * TILE_SIZE) - margin \
		and pos.y >= margin and pos.y <= float(ISLAND_H * TILE_SIZE) - margin

## 判断位置是否离已放置的物件太近
func _too_close(placed: Array[Vector2], pos: Vector2, spacing: float) -> bool:
	for other: Vector2 in placed:
		if pos.distance_to(other) < spacing:
			return true
	return false

## 构建单个障碍物节点：贴图底部对齐节点原点（配合 Y 排序），
## StaticBody2D + 小圆形碰撞体盖住底部主干/根部
func _make_prop(def: PropDef, pos: Vector2) -> Node2D:
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = def.radius
	shape.shape = circle
	shape.position = Vector2(0.0, -def.radius)
	body.add_child(shape)

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _things_tex
	sprite.region_enabled = true
	sprite.region_rect = def.region
	sprite.offset = Vector2(0.0, -def.region.size.y * 0.5) # 原点落在贴图底部
	body.add_child(sprite)
	body.position = pos
	return body

## 沿岛屿边缘生成四面隐形围墙，把球挡在岛内
func _build_walls() -> void:
	var thickness: float = 32.0
	# 允许球滚到边缘瓦片上，但不能出岛（往内收 8 像素）
	var inner: Rect2 = Rect2(
		8.0, 8.0,
		float(ISLAND_W * TILE_SIZE) - 16.0,
		float(ISLAND_H * TILE_SIZE) - 16.0
	)
	_add_wall(Rect2(inner.position.x - thickness, inner.position.y - thickness, inner.size.x + thickness * 2.0, thickness)) # 上
	_add_wall(Rect2(inner.position.x - thickness, inner.end.y, inner.size.x + thickness * 2.0, thickness))                  # 下
	_add_wall(Rect2(inner.position.x - thickness, inner.position.y, thickness, inner.size.y))                               # 左
	_add_wall(Rect2(inner.end.x, inner.position.y, thickness, inner.size.y))                                                # 右

## 用给定矩形创建一面静态墙
func _add_wall(rect: Rect2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.position = rect.get_center()
	body.add_child(shape)
	# 围墙挂进 World，随后随分屏一起进入共享 World2D
	_world.add_child(body)
