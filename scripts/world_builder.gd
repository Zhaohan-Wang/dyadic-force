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
var _style: String = "scatter"
var _clear_points: Array[Vector2] = []  # 出生点/终点附近清空
var _level_id: String = ""  # author 模式按关卡 ID 分发手工布局

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
	_style = def.layout_style
	_level_id = def.level_id
	_clear_points = [def.spawn_point, def.goal_point]
	_setup_water()
	_setup_ground_and_decor()
	if _style == "lane":
		_build_lane_layout()
	elif _style == "author":
		_build_authored_layout()
	else:
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

## 手工动线布局：左出生 → 中间两组交错小障碍（轻微 S 形绕行）→ 右传送门。
## 上下沿用栅栏框出边界，四角摆装饰树；全部经 _make_prop 走 y-sort，遮挡正确。
func _build_lane_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	var cy: float = h * 0.5
	var placed: Array[Vector2] = []

	# 上下两排栅栏：贴着围墙线，视觉上框出可玩区域，几乎不压缩动线
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	# 四角装饰树（角落本来就到不了，纯装饰 + 遮挡层次）
	var trees: Array[PropDef] = _tree_defs()
	for corner: Vector2 in [
		Vector2(44.0, 48.0), Vector2(w - 44.0, 48.0),
		Vector2(44.0, h - 36.0), Vector2(w - 44.0, h - 36.0),
	]:
		_world.add_child(_make_prop(trees[0], corner))

	# 中段障碍一：偏上的大树，逼球从下方绕
	_world.add_child(_make_prop(trees[1], Vector2(w * 0.38, cy - 30.0)))
	# 中段障碍二：偏下的石头组，逼球回到上方
	var rocks: Array[PropDef] = _rock_defs()
	_world.add_child(_make_prop(rocks[0], Vector2(w * 0.60, cy + 44.0)))
	_world.add_child(_make_prop(rocks[1], Vector2(w * 0.60 + 22.0, cy + 52.0)))

	# 路边点缀：小树 + 灌木，避开动线中轴
	var bushes: Array[PropDef] = _bush_defs()
	_world.add_child(_make_prop(trees[2], Vector2(w * 0.24, h - 44.0)))
	_world.add_child(_make_prop(bushes[0], Vector2(w * 0.48, 46.0)))
	_world.add_child(_make_prop(bushes[1], Vector2(w * 0.76, h - 46.0)))

	# 教程动线几乎水平：只在中轴放右箭头，避开障碍脚下
	_spawn_guide_arrow(Vector2(160.0, cy), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(300.0, cy + 16.0), Vector2.RIGHT)  # S 弯下缘
	_spawn_guide_arrow(Vector2(400.0, cy), Vector2.RIGHT)

	# 地面小草花：加密 decor 层（无碰撞、永远在球下面）
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 7
	for x: int in range(1, _island_w - 1):
		for y: int in range(1, _island_h - 1):
			if rng.randf() < 0.06:
				var pick: Vector2i = DECOR_TILES[rng.randi_range(0, DECOR_TILES.size() - 1)]
				_decor_layer.set_cell(Vector2i(x, y), SOURCE_ID, pick)

## 一整排水平栅栏（不做 clear point 检查，用于框边界）
func _spawn_fence_row(start: Vector2, segments: int) -> void:
	for i: int in segments:
		var pos: Vector2 = start + Vector2(16.0 * float(i), 0.0)
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
		_world.add_child(body)

# ---------- 手工关卡布局（author 模式） ----------
# 设计原则：先定球的行进路线，再沿路线两侧摆障碍。
# 球半径 44px（直径 88px），所有通道都按「球心可行区间 ≥ 40px」校核过，
# 即物理空隙 ≥ 128px，正常操作不会卡死。坐标改动前务必重新核算。

## 按关卡 ID 分发手工布局；未知 ID 回退到随机散布。
## 注意：第 2、3 关刻意共用同一张图（差异将来自输入增益等规则，而非地图）。
func _build_authored_layout() -> void:
	match _level_id:
		"level_1":
			_build_level1_layout()
		"level_2", "level_3":
			_build_gauntlet_layout()
		_:
			_spawn_obstacles()

## 第 1 关（832x320）：三道闸门缓弯 + 一道窄缝石门。
## 闸 1 上树墙（x=200，伸到 y=140，球从下过：球心 y ≥ 184）
## 闸 2 下石墙（x=340，伸到 y=274，球从上过：球心 y ≤ 215）
## 闸 3 上树墙（x=480，同闸 1）
## 闸 4 窄缝石门（x=610，上下石柱夹出球心带宽 50px 的缝，中心 y=170）
func _build_level1_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	var trees: Array[PropDef] = _tree_defs()
	var rocks: Array[PropDef] = _rock_defs()

	for cy: float in [56.0, 98.0, 140.0]:
		_world.add_child(_make_prop(trees[1], Vector2(200.0, cy)))
	for cy: float in [300.0, 274.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(340.0, cy)))
	_world.add_child(_make_prop(rocks[1], Vector2(358.0, 290.0)))
	for cy: float in [56.0, 98.0, 140.0]:
		_world.add_child(_make_prop(trees[0], Vector2(480.0, cy)))
	# 窄缝石门：上柱 + 下柱
	for cy: float in [49.0, 75.0, 101.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(610.0, cy)))
	for cy: float in [254.0, 280.0, 306.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(610.0, cy)))

	# 地面箭头：只标在该段真实行进方向上（本关以水平缓弯为主）
	_spawn_guide_arrow(Vector2(130.0, 200.0), Vector2.RIGHT)   # 开局右行
	_spawn_guide_arrow(Vector2(200.0, 220.0), Vector2.RIGHT)   # 闸 1 下方通道
	_spawn_guide_arrow(Vector2(340.0, 170.0), Vector2.RIGHT)   # 闸 2 上方通道
	_spawn_guide_arrow(Vector2(480.0, 220.0), Vector2.RIGHT)   # 闸 3 下方通道
	_spawn_guide_arrow(Vector2(610.0, 170.0), Vector2.RIGHT)   # 窄缝正中 → 终点

	_spawn_corner_trees(w, h)
	_sprinkle_decor(7)

## 第 2/3 关共用融合图（1056x544）：垂直闸门蛇形 + 中央树丛绕动 + 三处窄缝。
## 已用 BFS 全图可达性验证：唯一路线拓扑为
##   钻 T1 下方窄缝（石头收窄，球心带宽 45px）→ 井内爬升 → 翻 B1 顶端
##   → 顶部高跑 → 顶部短墙下压窄缝 → 越树丛顶 → 沿树丛右缘下潜
##   → 底部石缝 → 贴右墙爬升（T2 强制）→ 终点。
## 树丛脚下两棵灌木（655/745, 375）用于封死树丛与 B2 之间的针眼缝隙，勿删。
func _build_gauntlet_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	var rocks: Array[PropDef] = _rock_defs()

	# T1：顶部垂直墙 x=230（伸到 y=322，球从下方钻过）
	_spawn_bush_line(Vector2(230.0, 36.0), Vector2(0.0, 13.0), 23)
	# T1 窄缝石：把下潜口收窄到球心带宽 45px
	_world.add_child(_make_prop(rocks[0], Vector2(230.0, 470.0)))
	# B1：底部垂直墙 x=420（伸到 y=238，球翻越顶端）
	_spawn_bush_line(Vector2(420.0, h - 20.0), Vector2(0.0, -13.0), 23)
	# 顶部短墙 x=610（伸到 y=114）：高跑段被压低，与树丛顶夹出窄缝
	_spawn_bush_line(Vector2(610.0, 36.0), Vector2(0.0, 13.0), 7)
	# B2：底部短墙 x=700（树丛正下方，与树丛联合封死下方通道）
	_spawn_bush_line(Vector2(700.0, h - 20.0), Vector2(0.0, -13.0), 10)
	# 针眼封口灌木（树丛两脚）
	var bushes: Array[PropDef] = _bush_defs()
	_world.add_child(_make_prop(bushes[0], Vector2(655.0, 375.0)))
	_world.add_child(_make_prop(bushes[1], Vector2(745.0, 375.0)))

	# 中央树丛：1 棵中心 + 半径 45px 六棵环（球心须离中心 ≥ 101px）
	var trees: Array[PropDef] = _tree_defs()
	var cx: float = 700.0
	var cy: float = 272.0
	_world.add_child(_make_prop(trees[1], Vector2(cx, cy + 12.0)))
	for i: int in 6:
		var ang: float = TAU / 6.0 * float(i)
		var pos: Vector2 = Vector2(cx + 45.0 * cos(ang), cy + 45.0 * sin(ang) + 12.0)
		_world.add_child(_make_prop(trees[i % 2], pos))

	# T2：顶部垂直墙 x=890（伸到 y=244，强制最后贴右墙爬升）
	_spawn_bush_line(Vector2(890.0, 36.0), Vector2(0.0, 13.0), 17)
	# 底部石缝：T2 柱下方通道收窄（球心带宽 83px）
	_world.add_child(_make_prop(rocks[0], Vector2(890.0, 430.0)))

	# 地面箭头：严格跟蛇形动线的当前段方向，纵向段绝不用右箭头
	_spawn_guide_arrow(Vector2(140.0, 400.0), Vector2.RIGHT)  # 开局右行去 T1 底
	_spawn_guide_arrow(Vector2(230.0, 430.0), Vector2.RIGHT)  # 钻 T1 下方窄缝
	_spawn_guide_arrow(Vector2(330.0, 320.0), Vector2.UP)     # 井内爬升翻 B1
	_spawn_guide_arrow(Vector2(520.0, 100.0), Vector2.RIGHT)  # 顶部高跑
	_spawn_guide_arrow(Vector2(700.0, 120.0), Vector2.RIGHT)  # 越树丛顶
	_spawn_guide_arrow(Vector2(800.0, 260.0), Vector2.DOWN)   # 沿树丛右缘下潜
	_spawn_guide_arrow(Vector2(940.0, 380.0), Vector2.UP)     # 贴右墙爬升进门

	_spawn_corner_trees(w, h)
	_sprinkle_decor(9)

## 一串灌木（有碰撞的软墙），从 start 沿 step 连摆 count 棵
func _spawn_bush_line(start: Vector2, step: Vector2, count: int) -> void:
	var bushes: Array[PropDef] = _bush_defs()
	for i: int in count:
		_world.add_child(_make_prop(bushes[i % bushes.size()], start + step * float(i)))

## 引导箭头贴图缓存（本次 build 内复用）
var _arrow_tex: Texture2D = null

## 地面方向引导箭头（水印）。
## dir 必须是该段真实行进方向（RIGHT/LEFT/UP/DOWN），贴图默认朝右再旋转。
## 压在地面贴花层，无碰撞；位置应落在通道中心，避开障碍脚下。
func _spawn_guide_arrow(pos: Vector2, dir: Vector2) -> void:
	if _arrow_tex == null:
		_arrow_tex = _bake_arrow_texture()
	var holder: Node2D = Node2D.new()
	holder.position = pos
	holder.z_index = -1
	holder.z_as_relative = false
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _arrow_tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 烘焙箭头尖端朝右；用 angle 对齐到目标方向
	sprite.rotation = dir.normalized().angle()
	holder.add_child(sprite)
	_world.add_child(holder)

## 烘焙 16x16 右向像素箭头（深棕 + 低透明度水印感），最近邻放大 3 倍
func _bake_arrow_texture() -> Texture2D:
	var rows: Array[String] = [
		"................",
		"................",
		"................",
		".........XX.....",
		".........XXX....",
		"..XXXXXXXXXXX...",
		"..XXXXXXXXXXXX..",
		"..XXXXXXXXXXXX..",
		"..XXXXXXXXXXX...",
		".........XXX....",
		".........XX.....",
		"................",
		"................",
		"................",
		"................",
		"................",
	]
	var ink: Color = Color(0.29, 0.20, 0.11, 0.24)
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in 16:
		for x: int in 16:
			if rows[y][x] == "X":
				img.set_pixel(x, y, ink)
	img.resize(48, 48, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

## 四角装饰树：位置紧贴角落，均远离动线（已校核不侵入任何通道）
func _spawn_corner_trees(w: float, h: float) -> void:
	var trees: Array[PropDef] = _tree_defs()
	for corner: Vector2 in [
		Vector2(36.0, 40.0), Vector2(w - 36.0, 40.0),
		Vector2(36.0, h - 8.0), Vector2(w - 36.0, h - 8.0),
	]:
		_world.add_child(_make_prop(trees[0], corner))

## 地面草花点缀（decor 层无碰撞，密度按百分比）
func _sprinkle_decor(percent: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 7
	for x: int in range(1, _island_w - 1):
		for y: int in range(1, _island_h - 1):
			if rng.randi_range(0, 99) < percent:
				var pick: Vector2i = DECOR_TILES[rng.randi_range(0, DECOR_TILES.size() - 1)]
				_decor_layer.set_cell(Vector2i(x, y), SOURCE_ID, pick)

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
