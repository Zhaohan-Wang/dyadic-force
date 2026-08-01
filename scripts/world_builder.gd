class_name WorldBuilder
extends RefCounted
## 程序化建岛工具：根据 LevelDef 铺水面/草地/装饰/障碍/围墙。
## 不持有场景节点生命周期，由 Level 注入各层引用后调用 build()。

const TILE_SIZE: int = 16
const WATER_MARGIN: int = 12
const SOURCE_ID: int = 0

const DECOR_TILES: Array[Vector2i] = [
	Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5),
	Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
]

## 障碍物定义：图集区域 + 碰撞半径
class PropDef:
	var region: Rect2
	var radius: float

	func _init(p_region: Rect2, p_radius: float) -> void:
		region = p_region
		radius = p_radius

var _grass_tex: Texture2D = preload("res://assets/tiles/grass.png")
var _water_tex: Texture2D = preload("res://assets/tiles/water.png")
var _things_tex: Texture2D = preload("res://assets/objects/grass_biome_things.png")
var _fence_tex: Texture2D = preload("res://assets/tiles/fences.png")

var _water_layer: TileMapLayer
var _ground_layer: TileMapLayer
var _decor_layer: TileMapLayer
var _world: Node2D
var _island_w: int = 30
var _island_h: int = 18
var _seed: int = 20260801
var _density: float = 1.0
var _clear_points: Array[Vector2] = []  # 出生点/终点附近清空

## 绑定场景节点引用
func bind(
	water_layer: TileMapLayer,
	ground_layer: TileMapLayer,
	decor_layer: TileMapLayer,
	world: Node2D
) -> void:
	_water_layer = water_layer
	_ground_layer = ground_layer
	_decor_layer = decor_layer
	_world = world

## 按 LevelDef 构建整座岛
func build(def: LevelDef) -> void:
	_island_w = def.island_size.x
	_island_h = def.island_size.y
	_seed = def.layout_seed
	_density = maxf(0.3, def.obstacle_density)
	_clear_points = [def.spawn_point, def.goal_point]
	_setup_water()
	_setup_ground_and_decor()
	_spawn_obstacles()
	_build_walls()

## 岛屿像素宽高（供相机限位）
func island_size_px() -> Vector2i:
	return Vector2i(_island_w * TILE_SIZE, _island_h * TILE_SIZE)

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
	for x: int in range(-WATER_MARGIN, _island_w + WATER_MARGIN):
		for y: int in range(-WATER_MARGIN, _island_h + WATER_MARGIN):
			_water_layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i.ZERO)

func _setup_ground_and_decor() -> void:
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = _grass_tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
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
	for x: int in _island_w:
		for y: int in _island_h:
			var ax: int = 0 if x == 0 else (2 if x == _island_w - 1 else 1)
			var ay: int = 0 if y == 0 else (2 if y == _island_h - 1 else 1)
			_ground_layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i(ax, ay))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for x: int in range(1, _island_w - 1):
		for y: int in range(1, _island_h - 1):
			if rng.randf() < 0.09:
				var pick: Vector2i = DECOR_TILES[rng.randi_range(0, DECOR_TILES.size() - 1)]
				_decor_layer.set_cell(Vector2i(x, y), SOURCE_ID, pick)

func _tree_defs() -> Array[PropDef]:
	var defs: Array[PropDef] = []
	defs.append(PropDef.new(Rect2(16, 0, 32, 32), 12.0))
	defs.append(PropDef.new(Rect2(48, 0, 32, 32), 12.0))
	defs.append(PropDef.new(Rect2(0, 0, 16, 32), 8.0))
	return defs

func _rock_defs() -> Array[PropDef]:
	var defs: Array[PropDef] = []
	defs.append(PropDef.new(Rect2(128, 16, 16, 16), 7.5))
	defs.append(PropDef.new(Rect2(112, 16, 16, 16), 6.5))
	return defs

func _bush_defs() -> Array[PropDef]:
	var defs: Array[PropDef] = []
	defs.append(PropDef.new(Rect2(0, 48, 16, 16), 8.5))
	defs.append(PropDef.new(Rect2(16, 48, 16, 16), 8.5))
	return defs

func _spawn_obstacles() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 1
	var placed: Array[Vector2] = []
	var spawn: Vector2 = _clear_points[0] if _clear_points.size() > 0 else \
		Vector2(_island_w, _island_h) * float(TILE_SIZE) * 0.5

	# 栅栏位置按岛屿尺寸比例缩放
	var scale_x: float = float(_island_w) / 30.0
	var scale_y: float = float(_island_h) / 18.0
	_spawn_fence_line(Vector2(160.0 * scale_x, 96.0 * scale_y), 6, placed)
	_spawn_fence_line(Vector2(264.0 * scale_x, 208.0 * scale_y), 5, placed)

	var tree_clusters: int = maxi(1, int(round(2.0 * _density)))
	var rock_clusters: int = maxi(1, int(round(2.0 * _density)))
	for i: int in tree_clusters:
		_spawn_cluster(rng, placed, spawn, _tree_defs(), 5, 40.0)
	for i: int in rock_clusters:
		_spawn_cluster(rng, placed, spawn, _rock_defs(), 5, 24.0)

	_spawn_bush_wall(rng, placed, spawn, true)
	_spawn_bush_wall(rng, placed, spawn, false)
	if _density >= 1.0:
		_spawn_bush_wall(rng, placed, spawn, true)

	var loose: int = maxi(2, int(round(3.0 * _density)))
	for i: int in loose:
		_place_random(rng, placed, spawn, _tree_defs())
	for i: int in loose:
		_place_random(rng, placed, spawn, _rock_defs())

func _spawn_cluster(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	spawn: Vector2,
	variants: Array[PropDef],
	member_count: int,
	cluster_radius: float
) -> void:
	var anchor: Vector2 = _find_spot(rng, placed, 64.0, 96.0)
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
			if _near_clear(pos, 90.0):
				continue
			if _too_close(placed, pos, 18.0):
				continue
			placed.append(pos)
			var def: PropDef = variants[rng.randi_range(0, variants.size() - 1)]
			_world.add_child(_make_prop(def, pos))
			break

func _spawn_bush_wall(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	spawn: Vector2,
	horizontal: bool
) -> void:
	var bushes: Array[PropDef] = _bush_defs()
	var spacing: float = 13.0
	for attempt: int in 30:
		var count: int = rng.randi_range(4, 6)
		var dir: Vector2 = Vector2.RIGHT if horizontal else Vector2.DOWN
		var start: Vector2 = Vector2(
			rng.randf_range(48.0, float(_island_w * TILE_SIZE) - 48.0),
			rng.randf_range(48.0, float(_island_h * TILE_SIZE) - 48.0)
		)
		var ok: bool = true
		for i: int in count:
			var pos: Vector2 = start + dir * spacing * float(i)
			if not _is_inside_island(pos, 28.0) or _near_clear(pos, 90.0) \
					or _too_close(placed, pos, 20.0):
				ok = false
				break
		if not ok:
			continue
		for i: int in count:
			var pos: Vector2 = start + dir * spacing * float(i)
			placed.append(pos)
			_world.add_child(_make_prop(bushes[i % bushes.size()], pos))
		return

func _spawn_fence_line(start: Vector2, segments: int, placed: Array[Vector2]) -> void:
	for i: int in segments:
		var pos: Vector2 = start + Vector2(16.0 * float(i), 0.0)
		if _near_clear(pos, 70.0):
			continue
		var body: StaticBody2D = StaticBody2D.new()
		body.position = pos
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _fence_tex
		sprite.region_enabled = true
		var col: int = 1 if i == 0 else (3 if i == segments - 1 else 2)
		sprite.region_rect = Rect2(float(col) * 16.0, 48.0, 16.0, 16.0)
		sprite.offset = Vector2(0.0, -8.0)
		body.add_child(sprite)
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(16.0, 9.0)
		shape.shape = box
		shape.position = Vector2(0.0, -5.0)
		body.add_child(shape)
		placed.append(pos)
		_world.add_child(body)

func _place_random(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	_spawn: Vector2,
	variants: Array[PropDef]
) -> void:
	var pos: Vector2 = _find_spot(rng, placed, 32.0, 34.0)
	if pos == Vector2.INF:
		return
	placed.append(pos)
	var def: PropDef = variants[rng.randi_range(0, variants.size() - 1)]
	_world.add_child(_make_prop(def, pos))

func _find_spot(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	margin: float,
	spacing: float
) -> Vector2:
	for attempt: int in 60:
		var pos: Vector2 = Vector2(
			rng.randf_range(margin, float(_island_w * TILE_SIZE) - margin),
			rng.randf_range(margin, float(_island_h * TILE_SIZE) - margin)
		)
		if _near_clear(pos, 100.0):
			continue
		if _too_close(placed, pos, spacing):
			continue
		return pos
	return Vector2.INF

func _near_clear(pos: Vector2, radius: float) -> bool:
	for p: Vector2 in _clear_points:
		if pos.distance_to(p) < radius:
			return true
	return false

func _is_inside_island(pos: Vector2, margin: float) -> bool:
	return pos.x >= margin and pos.x <= float(_island_w * TILE_SIZE) - margin \
		and pos.y >= margin and pos.y <= float(_island_h * TILE_SIZE) - margin

func _too_close(placed: Array[Vector2], pos: Vector2, spacing: float) -> bool:
	for other: Vector2 in placed:
		if pos.distance_to(other) < spacing:
			return true
	return false

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
	sprite.offset = Vector2(0.0, -def.region.size.y * 0.5)
	body.add_child(sprite)
	body.position = pos
	return body

func _build_walls() -> void:
	var thickness: float = 32.0
	var inner: Rect2 = Rect2(
		8.0, 8.0,
		float(_island_w * TILE_SIZE) - 16.0,
		float(_island_h * TILE_SIZE) - 16.0
	)
	_add_wall(Rect2(inner.position.x - thickness, inner.position.y - thickness, inner.size.x + thickness * 2.0, thickness))
	_add_wall(Rect2(inner.position.x - thickness, inner.end.y, inner.size.x + thickness * 2.0, thickness))
	_add_wall(Rect2(inner.position.x - thickness, inner.position.y, thickness, inner.size.y))
	_add_wall(Rect2(inner.end.x, inner.position.y, thickness, inner.size.y))

func _add_wall(rect: Rect2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.position = rect.get_center()
	body.add_child(shape)
	_world.add_child(body)
