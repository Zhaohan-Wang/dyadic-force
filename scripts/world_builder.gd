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
## 灌木占格：同一 16px 格只放一棵，避免花叠花
var _bush_cells: Dictionary[Vector2i, bool] = {}
## 门板禁放区：灌木不得长到门上
var _gate_keepout: Array[Rect2] = []
## 本关门配置：曲线关卡据此自动留出门板禁放区
var _gate_defs: Array[GateDef] = []
## 走廊占用网格（曲线关卡）：布景一律不许摆到路面上
var _route_grid: PackedByteArray = PackedByteArray()
var _route_nx: int = 0
var _route_ny: int = 0

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
	_gate_defs = def.gates
	_bush_cells.clear()
	_gate_keepout.clear()
	_route_grid = PackedByteArray()
	_route_nx = 0
	_route_ny = 0
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
	# 异形岛岸线（边缘 + 内凹缺角）与整块草地变体
	for coords: Vector2i in LAND_EDGE_TILES.values():
		if not source.has_tile(coords):
			source.create_tile(coords)
	for coords: Vector2i in LAND_NOTCH_TILES.values():
		if not source.has_tile(coords):
			source.create_tile(coords)
	for group: Array[Vector2i] in [GROUND_GRASSY, GROUND_SUBTLE, GROUND_PATCHY, GROUND_BRIGHT, GROUND_FLOWERY]:
		for coords: Vector2i in group:
			if not source.has_tile(coords):
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
	# 手工关卡（1~5）的地面全部由 _paint_land 重铺，不需要旧的随机花草贴图层
	if _style == "author":
		return
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
		body.add_to_group("ordinary_obstacle")
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
# 球半径 44px（直径 88px）；新图最低物理空隙 ≥ 150px（球心可行带 ≥ 62px）。
# STRETCH 注释段只加长度、不改机制，供试玩校准总时长。

## 按关卡 ID 分发手工布局；未知 ID 回退到随机散布。
func _build_authored_layout() -> void:
	match _level_id:
		"level_1":
			_build_level1_layout()
		"level_2":
			_build_level2_layout()
		"level_3":
			_build_level3_layout()
		"level_4":
			_build_level4_layout()
		"level_5":
			_build_level5_layout()
		_:
			_spawn_obstacles()

## 第 1 关「三门直道」：几何完全沿用原设计（两条直道 + 两个直角缓弯 + 三道门），
## 只把表现层换成第 3~5 关那一套：自动岸线、分区植被、地面质感、封死区隐形块。
## 中心线与 level_1.tres 的 route_centerline 逐点一致，半宽 110，实验路线误差指标不受影响。
## 岛屿 140×40 瓦 = 2240×640。
func _plan_level1() -> LevelPlan:
	var plan: LevelPlan = LevelPlan.new()
	plan.island = Vector2i(140, 40)
	plan.straight = true
	plan.water_border = 2
	plan.arrow_spacing = 300.0
	var half: float = 110.0
	plan.spine = [
		RouteNode.new(Vector2(120.0, 176.0), half),
		RouteNode.new(Vector2(520.0, 176.0), half),
		RouteNode.new(Vector2(800.0, 176.0), half),
		RouteNode.new(Vector2(800.0, 464.0), half),
		RouteNode.new(Vector2(1220.0, 464.0), half),
		RouteNode.new(Vector2(1520.0, 464.0), half),
		RouteNode.new(Vector2(1520.0, 176.0), half),
		RouteNode.new(Vector2(1900.0, 176.0), half),
		RouteNode.new(Vector2(2160.0, 176.0), half),
	]
	# 三段风貌：起步林地 → 中段草甸（第二道门）→ 收尾岩地（第三道门）
	plan.zones = [
		SceneZone.new(Rect2(760.0, 0.0, 780.0, 640.0), "meadow"),
		SceneZone.new(Rect2(1540.0, 0.0, 700.0, 640.0), "rock"),
	]
	return plan

func _build_level1_layout() -> void:
	_realize_plan(_plan_level1())

## 门板禁放区：栅栏门很薄，左右各留一截，上下盖住开口。
func _add_gate_keepout(center: Vector2, opening: float) -> void:
	_gate_keepout.append(
		Rect2(center.x - 28.0, center.y - opening * 0.5 - 10.0, 56.0, opening + 20.0)
	)

## 不可见实心障碍块（普通障碍，撞了仍扣血），用来填死角防抄近道。
func _add_obstacle_block(rect: Rect2) -> void:
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	var body: StaticBody2D = StaticBody2D.new()
	body.add_to_group("ordinary_obstacle")
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.position = rect.get_center()
	body.add_child(shape)
	_world.add_child(body)

## 走廊外全部封死：把占用网格里的空白格贪心合并成大矩形，减少静态体数量。
## 封死块不可见，视觉完全交给布景（树/石/花/水面）。
func _seal_from_grid(grid: PackedByteArray, nx: int, ny: int) -> void:
	var used: PackedByteArray = PackedByteArray()
	used.resize(nx * ny)
	for iy: int in ny:
		for ix: int in nx:
			var idx: int = iy * nx + ix
			if grid[idx] == 1 or used[idx] == 1:
				continue
			# 先向右扩到最宽
			var w_cells: int = 0
			while ix + w_cells < nx:
				var i2: int = iy * nx + ix + w_cells
				if grid[i2] == 1 or used[i2] == 1:
					break
				w_cells += 1
			# 再整行向下扩
			var h_cells: int = 1
			while iy + h_cells < ny:
				var row_ok: bool = true
				for k: int in w_cells:
					var i3: int = (iy + h_cells) * nx + ix + k
					if grid[i3] == 1 or used[i3] == 1:
						row_ok = false
						break
				if not row_ok:
					break
				h_cells += 1
			for ry: int in h_cells:
				for rx: int in w_cells:
					used[(iy + ry) * nx + ix + rx] = 1
			_add_obstacle_block(Rect2(
				float(ix) * SCENE_CELL,
				float(iy) * SCENE_CELL,
				float(w_cells) * SCENE_CELL,
				float(h_cells) * SCENE_CELL
			))

## 第 2 关「折返直道」：三条长直道 + 两个回转（共同减速）。几何沿用原设计，
## 中心线与 level_2.tres 逐点一致，半宽 90；表现层换成统一的岸线 / 分区植被 / 地面质感。
## 车道之间只剩 30~50px 隔离带，正好长成一排密树篱，比原来一条稀疏灌木线好认。
## 岛屿 80×42 瓦 = 1280×672。
func _plan_level2() -> LevelPlan:
	var plan: LevelPlan = LevelPlan.new()
	plan.island = Vector2i(80, 42)
	plan.straight = true
	plan.water_border = 2
	plan.arrow_spacing = 260.0
	var half: float = 90.0
	plan.spine = [
		RouteNode.new(Vector2(100.0, 580.0), half),
		RouteNode.new(Vector2(400.0, 580.0), half),
		RouteNode.new(Vector2(800.0, 580.0), half),
		RouteNode.new(Vector2(1100.0, 580.0), half),
		RouteNode.new(Vector2(1140.0, 420.0), half),
		RouteNode.new(Vector2(900.0, 370.0), half),
		RouteNode.new(Vector2(500.0, 370.0), half),
		RouteNode.new(Vector2(160.0, 370.0), half),
		RouteNode.new(Vector2(140.0, 200.0), half),
		RouteNode.new(Vector2(300.0, 140.0), half),
		RouteNode.new(Vector2(700.0, 140.0), half),
		RouteNode.new(Vector2(1180.0, 140.0), half),
	]
	# 车道之间的隔离带只有 30~50px，必须长成密林才看得出"这里过不去"；
	# 换成草甸的小花会让玩家以为能穿过去（那里其实有隐形封死块）。
	plan.zones = [
		SceneZone.new(Rect2(0.0, 440.0, 1280.0, 62.0), "deep_forest"),
		SceneZone.new(Rect2(0.0, 216.0, 1280.0, 70.0), "deep_forest"),
	]
	return plan

func _build_level2_layout() -> void:
	_realize_plan(_plan_level2())

# ---------- 曲线路线系统（第 3 / 4 / 5 关） ----------
# 借鉴通用赛道 / 关卡设计经验：
# - 弯型配比大致 40% 高速缓弯、35% 中速弯、25% 技术紧弯，不出现直角拐；
# - 宽度本身就是难度信号：窄 = 紧张，宽 = 放松，难点之后必须接恢复段；
# - 相邻段落切线连续（Catmull-Rom 样条），避免曲率跳变带来的"程序化感"；
# - 每个区块换植被与地面质感，玩家可以靠景物辨认自己走到哪儿了。

## 布景 / 光栅化网格步长（与瓦片同尺寸）
const SCENE_CELL: float = 16.0
## 走廊外保留的陆地层数（每层 16px），再往外露出水面。
## 刻意压薄：路边一圈密林紧贴隐形墙，再几步就是水，玩家一眼能看出哪儿是路。
const LAND_BAND_CELLS: int = 5
## 可整块铺地的草地变体（grass.png 第 5、6 行，全部不透明）
const GROUND_PLAIN: Vector2i = Vector2i(1, 1)
const GROUND_GRASSY: Array[Vector2i] = [Vector2i(0, 5), Vector2i(1, 5), Vector2i(0, 6), Vector2i(1, 6)]
const GROUND_SUBTLE: Array[Vector2i] = [Vector2i(2, 5), Vector2i(2, 6)]
const GROUND_PATCHY: Array[Vector2i] = [Vector2i(3, 5), Vector2i(3, 6)]
const GROUND_BRIGHT: Array[Vector2i] = [Vector2i(4, 5), Vector2i(4, 6)]
const GROUND_FLOWERY: Array[Vector2i] = [Vector2i(5, 5), Vector2i(5, 6)]

## 陆地边缘瓦片：四邻遮罩（N=1 E=2 S=4 W=8，置位 = 该侧也是陆地）。
## 每格取值都按 grass.png 的实测透明边框校对过：某侧整条边透明 = 该侧朝水。
const LAND_EDGE_TILES: Dictionary[int, Vector2i] = {
	# 单侧朝水：北岸 / 南岸 / 东岸 / 西岸
	14: Vector2i(1, 0), 11: Vector2i(1, 2), 13: Vector2i(2, 1), 7: Vector2i(0, 1),
	# 两侧朝水的外角
	6: Vector2i(0, 0), 12: Vector2i(2, 0), 3: Vector2i(0, 2), 9: Vector2i(2, 2),
	# 一格宽的地峡：竖条 / 横条
	5: Vector2i(3, 1), 10: Vector2i(1, 3),
	# 半岛端头：向南 / 向北 / 向东 / 向西伸出
	4: Vector2i(3, 0), 1: Vector2i(3, 2), 2: Vector2i(0, 3), 8: Vector2i(2, 3),
	# 孤立一格
	0: Vector2i(3, 3),
}

## 内凹缺角瓦片：对角遮罩（NW=1 NE=2 SW=4 SE=8，置位 = 该对角是水）
const LAND_NOTCH_TILES: Dictionary[int, Vector2i] = {
	1: Vector2i(6, 2), 2: Vector2i(5, 2), 4: Vector2i(6, 1), 8: Vector2i(5, 1),
	9: Vector2i(9, 0), 6: Vector2i(9, 1), 3: Vector2i(8, 2), 12: Vector2i(8, 1),
	5: Vector2i(6, 4), 10: Vector2i(5, 4),
	7: Vector2i(9, 2), 11: Vector2i(10, 2), 13: Vector2i(9, 3), 14: Vector2i(10, 3),
	15: Vector2i(9, 4),
}

## 路线控制点：位置 + 该点走廊半宽 + 手柄张力（>1 更缓，<1 更紧）
class RouteNode:
	var pos: Vector2
	var half: float
	var tension: float

	func _init(p_pos: Vector2, p_half: float, p_tension: float = 1.0) -> void:
		pos = p_pos
		half = p_half
		tension = p_tension

## 采样后的中心线：点列 + 每点半宽
class RouteLine:
	var points: Array[Vector2] = []
	var halves: PackedFloat32Array = PackedFloat32Array()

	## 中心线总长（像素）
	func length() -> float:
		var total: float = 0.0
		for i: int in range(points.size() - 1):
			total += points[i].distance_to(points[i + 1])
		return total

	## 最小半宽（用于校核通道是否够球通过）
	func min_half() -> float:
		var m: float = 9999.0
		for h: float in halves:
			m = minf(m, h)
		return m

## 岔路分支：控制点 + 标签（窄短 / 宽长）
class RouteBranch:
	var nodes: Array[RouteNode] = []
	var label: String = ""

	func _init(p_nodes: Array[RouteNode], p_label: String) -> void:
		nodes = p_nodes
		label = p_label

## 布景分区：矩形范围（作者坐标）+ 风貌类型
class SceneZone:
	var rect: Rect2
	var kind: String

	func _init(p_rect: Rect2, p_kind: String) -> void:
		rect = p_rect
		kind = p_kind

## 单关手工路线计划：主路 + 支路 + 分区 + 水面 + 地标。
## 控制点用"作者坐标"，realize 时统一加 origin，方便整体挪动留出水面边距。
class LevelPlan:
	var origin: Vector2 = Vector2.ZERO
	var island: Vector2i = Vector2i(140, 100)
	## true = 控制点按直线折线连接（第 1/2 关沿用原直角几何，不做曲线平滑）
	var straight: bool = false
	## 岛屿四周强制变水的瓦片圈数（0 = 不留水框）；只切离走廊够远的格
	var water_border: int = 0
	## 主路第一段
	var spine: Array[RouteNode] = []
	## 其余路段：岔路分支与主路后续段，label 供中心线拼接
	var branches: Array[RouteBranch] = []
	## 安全路线（写入 tres route_centerline）的拼接顺序，"spine" 代表主路第一段
	var centerline_order: PackedStringArray = PackedStringArray(["spine"])
	var zones: Array[SceneZone] = []
	## 额外水湾：切进陆地带，制造不规则岸线
	var water_cuts: Array[Rect2] = []
	## 额外陆地：树林 / 半岛，避免整张图只有一条等宽绿带
	var land_extra: Array[Rect2] = []
	## 地标：{"pos": Vector2, "kind": String}
	var landmarks: Array[Dictionary] = []
	## 木栅栏点缀：{"pos": Vector2, "count": int}
	var fences: Array[Dictionary] = []
	var arrow_spacing: float = 340.0

## 三次贝塞尔取点
func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t) + d * (t * t * t)

## 控制点列表 → 平滑中心线（Catmull-Rom 转三次贝塞尔，切线自动连续）
func _sample_route(nodes: Array[RouteNode], step: float = 22.0) -> RouteLine:
	var line: RouteLine = RouteLine.new()
	if nodes.size() < 2:
		return line
	line.points.append(nodes[0].pos)
	line.halves.append(nodes[0].half)
	for i: int in range(nodes.size() - 1):
		var n1: RouteNode = nodes[i]
		var n2: RouteNode = nodes[i + 1]
		var p0: Vector2 = nodes[i - 1].pos if i > 0 else n1.pos * 2.0 - n2.pos
		var p3: Vector2 = nodes[i + 2].pos if i + 2 < nodes.size() else n2.pos * 2.0 - n1.pos
		var c1: Vector2 = n1.pos + (n2.pos - p0) / 6.0 * n1.tension
		var c2: Vector2 = n2.pos - (p3 - n1.pos) / 6.0 * n2.tension
		var rough: float = n1.pos.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(n2.pos)
		var steps: int = maxi(4, int(ceil(rough / step)))
		for s: int in range(1, steps + 1):
			var t: float = float(s) / float(steps)
			line.points.append(_bezier(n1.pos, c1, c2, n2.pos, t))
			line.halves.append(lerpf(n1.half, n2.half, t))
	return line

## 控制点列表 → 折线中心线（不平滑，直角保持直角；第 1/2 关用）
func _sample_polyline(nodes: Array[RouteNode], step: float = 22.0) -> RouteLine:
	var line: RouteLine = RouteLine.new()
	if nodes.size() < 2:
		return line
	line.points.append(nodes[0].pos)
	line.halves.append(nodes[0].half)
	for i: int in range(nodes.size() - 1):
		var n1: RouteNode = nodes[i]
		var n2: RouteNode = nodes[i + 1]
		var steps: int = maxi(1, int(ceil(n1.pos.distance_to(n2.pos) / step)))
		for s: int in range(1, steps + 1):
			var t: float = float(s) / float(steps)
			line.points.append(n1.pos.lerp(n2.pos, t))
			line.halves.append(lerpf(n1.half, n2.half, t))
	return line

## 按计划选择采样方式：曲线关卡走样条，直角关卡走折线
func _sample_plan_line(nodes: Array[RouteNode], plan: LevelPlan) -> RouteLine:
	var shifted: Array[RouteNode] = _shift_nodes(nodes, plan.origin)
	return _sample_polyline(shifted) if plan.straight else _sample_route(shifted)

## 整条路线平移（作者坐标 → 世界坐标）
func _shift_nodes(nodes: Array[RouteNode], offset: Vector2) -> Array[RouteNode]:
	var out: Array[RouteNode] = []
	for n: RouteNode in nodes:
		out.append(RouteNode.new(n.pos + offset, n.half, n.tension))
	return out

## 点到线段的最近距离与参数 t
func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return Vector2(p.distance_to(a), 0.0)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return Vector2(p.distance_to(a + ab * t), t)

## 把若干条中心线按半宽刷进占用网格（1 = 可走）
func _rasterize_routes(lines: Array[RouteLine], nx: int, ny: int) -> PackedByteArray:
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(nx * ny)
	for line: RouteLine in lines:
		for i: int in range(line.points.size() - 1):
			var a: Vector2 = line.points[i]
			var b: Vector2 = line.points[i + 1]
			var ha: float = line.halves[i]
			var hb: float = line.halves[i + 1]
			var pad: float = maxf(ha, hb) + SCENE_CELL
			var x0: int = clampi(int(floor((minf(a.x, b.x) - pad) / SCENE_CELL)), 0, nx - 1)
			var x1: int = clampi(int(ceil((maxf(a.x, b.x) + pad) / SCENE_CELL)), 0, nx - 1)
			var y0: int = clampi(int(floor((minf(a.y, b.y) - pad) / SCENE_CELL)), 0, ny - 1)
			var y1: int = clampi(int(ceil((maxf(a.y, b.y) + pad) / SCENE_CELL)), 0, ny - 1)
			for iy: int in range(y0, y1 + 1):
				for ix: int in range(x0, x1 + 1):
					var idx: int = iy * nx + ix
					if grid[idx] == 1:
						continue
					var c: Vector2 = Vector2((float(ix) + 0.5) * SCENE_CELL, (float(iy) + 0.5) * SCENE_CELL)
					var hit: Vector2 = _segment_distance(c, a, b)
					if hit.x <= lerpf(ha, hb, hit.y):
						grid[idx] = 1
	return grid

## 到走廊的格距场：0 = 走廊内，1.. = 向外第几层，200 = 很远
func _corridor_distance(grid: PackedByteArray, nx: int, ny: int, max_d: int) -> PackedByteArray:
	var dist: PackedByteArray = PackedByteArray()
	dist.resize(nx * ny)
	var queue: PackedInt32Array = PackedInt32Array()
	for i: int in nx * ny:
		if grid[i] == 1:
			dist[i] = 0
			queue.append(i)
		else:
			dist[i] = 200
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var d: int = dist[idx]
		if d >= max_d:
			continue
		var ix: int = idx % nx
		var iy: int = idx / nx
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var jx: int = ix + step.x
			var jy: int = iy + step.y
			if jx < 0 or jy < 0 or jx >= nx or jy >= ny:
				continue
			var jdx: int = jy * nx + jx
			if dist[jdx] <= d + 1:
				continue
			dist[jdx] = d + 1
			queue.append(jdx)
	return dist

## 陆地遮罩：走廊 + 外侧若干层为陆地，另加作者指定的林地/半岛，再挖掉水湾
func _build_land_mask(
	dist: PackedByteArray,
	nx: int,
	ny: int,
	extra: Array[Rect2],
	cuts: Array[Rect2],
	border: int = 0
) -> PackedByteArray:
	var land: PackedByteArray = PackedByteArray()
	land.resize(nx * ny)
	for iy: int in ny:
		for ix: int in nx:
			var idx: int = iy * nx + ix
			land[idx] = 1 if dist[idx] <= LAND_BAND_CELLS else 0
	for rect: Rect2 in extra:
		_mark_ellipse(land, nx, ny, rect, 1, dist, -1)
	# 水湾只能挖在离走廊 3 层以外，免得把路面切断
	for rect: Rect2 in cuts:
		_mark_ellipse(land, nx, ny, rect, 0, dist, 3)
	# 岛屿外圈留一道水，让"整块绿矩形"变成有岸线的岛；同样只切离走廊够远的格
	for iy: int in ny:
		for ix: int in nx:
			if ix >= border and iy >= border and ix < nx - border and iy < ny - border:
				continue
			var idx: int = iy * nx + ix
			if int(dist[idx]) >= 3:
				land[idx] = 0
	return land

## 在遮罩上刷一个椭圆（内切于 rect）。min_dist >= 0 时只改动离走廊足够远的格。
## 用椭圆而不是矩形，湖和小岛才不会是方块。
func _mark_ellipse(
	mask: PackedByteArray,
	nx: int,
	ny: int,
	rect: Rect2,
	value: int,
	dist: PackedByteArray,
	min_dist: int
) -> void:
	var center: Vector2 = rect.get_center()
	var radii: Vector2 = rect.size * 0.5
	if radii.x < 1.0 or radii.y < 1.0:
		return
	var x0: int = clampi(int(floor(rect.position.x / SCENE_CELL)), 0, nx - 1)
	var x1: int = clampi(int(ceil(rect.end.x / SCENE_CELL)), 0, nx - 1)
	var y0: int = clampi(int(floor(rect.position.y / SCENE_CELL)), 0, ny - 1)
	var y1: int = clampi(int(ceil(rect.end.y / SCENE_CELL)), 0, ny - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var idx: int = iy * nx + ix
			if min_dist >= 0 and int(dist[idx]) < min_dist:
				continue
			var p: Vector2 = Vector2((float(ix) + 0.5) * SCENE_CELL, (float(iy) + 0.5) * SCENE_CELL)
			var d: Vector2 = (p - center) / radii
			if d.length_squared() <= 1.0:
				mask[idx] = value

## 取遮罩值（越界视为水）
func _mask_at(mask: PackedByteArray, nx: int, ny: int, ix: int, iy: int) -> int:
	if ix < 0 or iy < 0 or ix >= nx or iy >= ny:
		return 0
	return mask[iy * nx + ix]

## 按陆地遮罩铺地面瓦片：岸边用边缘 / 缺角瓦片，内部按分区换草地质感
func _paint_land(
	land: PackedByteArray,
	grid: PackedByteArray,
	dist: PackedByteArray,
	nx: int,
	ny: int,
	zones: Array[SceneZone],
	rng: RandomNumberGenerator
) -> void:
	for iy: int in ny:
		for ix: int in nx:
			var coords: Vector2i = Vector2i(ix, iy)
			if _mask_at(land, nx, ny, ix, iy) == 0:
				_ground_layer.erase_cell(coords)
				continue
			var mask4: int = 0
			mask4 |= 1 if _mask_at(land, nx, ny, ix, iy - 1) == 1 else 0
			mask4 |= 2 if _mask_at(land, nx, ny, ix + 1, iy) == 1 else 0
			mask4 |= 4 if _mask_at(land, nx, ny, ix, iy + 1) == 1 else 0
			mask4 |= 8 if _mask_at(land, nx, ny, ix - 1, iy) == 1 else 0
			if mask4 != 15:
				_ground_layer.set_cell(coords, SOURCE_ID, LAND_EDGE_TILES[mask4])
				continue
			var diag: int = 0
			diag |= 1 if _mask_at(land, nx, ny, ix - 1, iy - 1) == 0 else 0
			diag |= 2 if _mask_at(land, nx, ny, ix + 1, iy - 1) == 0 else 0
			diag |= 4 if _mask_at(land, nx, ny, ix - 1, iy + 1) == 0 else 0
			diag |= 8 if _mask_at(land, nx, ny, ix + 1, iy + 1) == 0 else 0
			if diag != 0:
				_ground_layer.set_cell(coords, SOURCE_ID, LAND_NOTCH_TILES[diag])
				continue
			_ground_layer.set_cell(coords, SOURCE_ID, _ground_variant(
				grid[iy * nx + ix] == 1,
				int(dist[iy * nx + ix]),
				_zone_kind(zones, Vector2((float(ix) + 0.5) * SCENE_CELL, (float(iy) + 0.5) * SCENE_CELL)),
				rng
			))

## 单格地面质感：路面干净、路肩杂草、草甸开花、岩地发暗
func _ground_variant(on_route: bool, layer: int, kind: String, rng: RandomNumberGenerator) -> Vector2i:
	if on_route:
		if rng.randf() < 0.18:
			return GROUND_SUBTLE[rng.randi_range(0, GROUND_SUBTLE.size() - 1)]
		return GROUND_PLAIN
	if kind == "meadow":
		if rng.randf() < 0.5:
			return GROUND_FLOWERY[rng.randi_range(0, GROUND_FLOWERY.size() - 1)]
		return GROUND_BRIGHT[rng.randi_range(0, GROUND_BRIGHT.size() - 1)]
	if kind == "rock":
		if rng.randf() < 0.6:
			return GROUND_PATCHY[rng.randi_range(0, GROUND_PATCHY.size() - 1)]
		return GROUND_SUBTLE[rng.randi_range(0, GROUND_SUBTLE.size() - 1)]
	# 路肩用带深色斑块的草，和路面的干净草形成明暗差，路的走向更好认
	if rng.randf() < 0.55:
		return GROUND_PATCHY[rng.randi_range(0, GROUND_PATCHY.size() - 1)]
	return GROUND_GRASSY[rng.randi_range(0, GROUND_GRASSY.size() - 1)]

## 该点属于哪个风貌分区（未命中 = 林地）
func _zone_kind(zones: Array[SceneZone], pos: Vector2) -> String:
	for z: SceneZone in zones:
		if z.rect.has_point(pos):
			return z.kind
	return "forest"

## 全部可用植被 / 石头 / 花素材（grass_biome_things.png 144×80，脚点对齐）
func _scenery_lib() -> Dictionary[String, PropDef]:
	var lib: Dictionary[String, PropDef] = {}
	lib["tree_big"] = PropDef.new(Rect2(16, 0, 32, 32), 12.0)
	lib["tree_flower"] = PropDef.new(Rect2(48, 0, 32, 32), 12.0)
	lib["tree_small"] = PropDef.new(Rect2(0, 0, 16, 32), 8.0)
	lib["bush_berry"] = PropDef.new(Rect2(0, 48, 16, 16), 8.5)
	lib["bush_plain"] = PropDef.new(Rect2(16, 48, 16, 16), 8.5)
	lib["rock_small"] = PropDef.new(Rect2(112, 16, 16, 16), 6.5)
	lib["rock_big"] = PropDef.new(Rect2(128, 16, 16, 16), 7.5)
	lib["rock_pile"] = PropDef.new(Rect2(64, 64, 16, 16), 7.0)
	lib["rock_dark"] = PropDef.new(Rect2(80, 64, 16, 16), 6.5)
	# 直立的树桩：代替原来那批横躺的枯木（躺着的看起来像树倒了）
	lib["stump_small"] = PropDef.new(Rect2(48, 32, 16, 16), 6.0)
	lib["stump_big"] = PropDef.new(Rect2(64, 32, 16, 16), 6.5)
	lib["berries"] = PropDef.new(Rect2(64, 48, 16, 16), 5.0)
	lib["mushroom_brown"] = PropDef.new(Rect2(80, 0, 16, 16), 6.0)
	lib["mushroom_purple"] = PropDef.new(Rect2(128, 0, 16, 16), 6.0)
	lib["leaves"] = PropDef.new(Rect2(80, 16, 16, 16), 5.0)
	lib["flower_yellow"] = PropDef.new(Rect2(112, 32, 16, 16), 5.0)
	lib["flower_pink"] = PropDef.new(Rect2(112, 48, 16, 16), 5.0)
	lib["sunflower"] = PropDef.new(Rect2(128, 32, 16, 32), 5.0)
	lib["lily_a"] = PropDef.new(Rect2(112, 64, 16, 16), 4.0)
	lib["lily_b"] = PropDef.new(Rect2(128, 64, 16, 16), 4.0)
	lib["lily_c"] = PropDef.new(Rect2(96, 64, 16, 16), 4.0)
	return lib

## 各风貌分区的植被权重表（字符串重复次数 = 权重），layer 1 = 紧贴走廊
func _scene_table(kind: String, layer: int) -> PackedStringArray:
	if kind == "rock":
		if layer <= 1:
			return PackedStringArray([
				"rock_small", "rock_small", "rock_big", "rock_big", "rock_pile",
				"rock_dark", "bush_plain", "stump_small",
			])
		if layer == 2:
			return PackedStringArray([
				"rock_big", "rock_pile", "rock_dark", "tree_small", "stump_big", "bush_plain",
			])
		return PackedStringArray(["rock_big", "rock_pile", "tree_big", "tree_small"])
	if kind == "meadow":
		if layer <= 1:
			return PackedStringArray([
				"flower_yellow", "flower_yellow", "flower_pink", "flower_pink",
				"bush_plain", "leaves", "leaves", "sunflower",
			])
		if layer == 2:
			return PackedStringArray([
				"sunflower", "flower_yellow", "flower_pink", "tree_small", "berries", "bush_berry",
			])
		return PackedStringArray(["tree_small", "tree_flower", "tree_big", "sunflower"])
	if kind == "shore":
		if layer <= 2:
			return PackedStringArray([
				"bush_plain", "bush_berry", "rock_small", "rock_pile",
				"leaves", "stump_small", "tree_small",
			])
		return PackedStringArray(["tree_small", "bush_plain", "rock_big", "tree_big"])
	if kind == "deep_forest":
		if layer <= 1:
			return PackedStringArray([
				"bush_berry", "bush_plain", "tree_small", "mushroom_brown",
				"mushroom_purple", "leaves", "stump_big",
			])
		return PackedStringArray([
			"tree_big", "tree_big", "tree_flower", "tree_small", "bush_plain",
		])
	if layer <= 1:
		return PackedStringArray([
			"bush_plain", "bush_berry", "bush_berry", "tree_small",
			"rock_small", "mushroom_brown", "leaves", "flower_pink",
		])
	if layer == 2:
		return PackedStringArray([
			"tree_big", "tree_flower", "tree_small", "tree_small", "bush_plain", "stump_small",
		])
	return PackedStringArray(["tree_big", "tree_big", "tree_flower", "rock_big"])

## 各风貌分区的摆放密度：贴着走廊的一层最密，形成连续的"软墙"，越往外越疏
func _scene_density(kind: String, layer: int) -> float:
	if kind == "meadow":
		return [0.0, 0.80, 0.46, 0.30][mini(layer, 3)]
	if kind == "rock":
		return [0.0, 0.86, 0.52, 0.34][mini(layer, 3)]
	if kind == "shore":
		return [0.0, 0.78, 0.62, 0.44][mini(layer, 3)]
	if kind == "deep_forest":
		return [0.0, 0.90, 0.62, 0.48][mini(layer, 3)]
	return [0.0, 0.88, 0.52, 0.36][mini(layer, 3)]

## 纯视觉植被：封死区已有隐形实心块挡球，不必给每棵树配物理体
func _make_scenery(def: PropDef, pos: Vector2) -> Node2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _things_tex
	sprite.region_enabled = true
	sprite.region_rect = def.region
	sprite.offset = Vector2(0.0, -def.region.size.y * 0.5)
	sprite.position = pos
	return sprite

## 摆一株布景：路面、门板禁区与已占格一律跳过
func _place_scene_prop(def: PropDef, pos: Vector2) -> void:
	for rect: Rect2 in _gate_keepout:
		if rect.has_point(pos):
			return
	var cell: Vector2i = Vector2i(int(floor(pos.x / SCENE_CELL)), int(floor(pos.y / SCENE_CELL)))
	if _route_nx > 0:
		if cell.x < 0 or cell.y < 0 or cell.x >= _route_nx or cell.y >= _route_ny:
			return
		if _route_grid[cell.y * _route_nx + cell.x] == 1:
			return
	if _bush_cells.has(cell):
		return
	_bush_cells[cell] = true
	_world.add_child(_make_scenery(def, pos))

## 按分区在封死区铺自然景观；抖动摆放，避免出现网格感
func _decorate_land(
	land: PackedByteArray,
	grid: PackedByteArray,
	dist: PackedByteArray,
	nx: int,
	ny: int,
	zones: Array[SceneZone],
	rng: RandomNumberGenerator
) -> void:
	var lib: Dictionary[String, PropDef] = _scenery_lib()
	for iy: int in ny:
		for ix: int in nx:
			var idx: int = iy * nx + ix
			if land[idx] == 0 or grid[idx] == 1:
				continue
			var pos: Vector2 = Vector2((float(ix) + 0.5) * SCENE_CELL, (float(iy) + 0.5) * SCENE_CELL)
			var layer: int = clampi(int(dist[idx]), 1, 3)
			var kind: String = _zone_kind(zones, pos)
			# 紧贴水面的一圈按岸线处理：密一点，遮住硬边
			var near_water: bool = _mask_at(land, nx, ny, ix + 1, iy) == 0 \
				or _mask_at(land, nx, ny, ix - 1, iy) == 0 \
				or _mask_at(land, nx, ny, ix, iy + 1) == 0 \
				or _mask_at(land, nx, ny, ix, iy - 1) == 0
			if near_water:
				kind = "shore"
			if rng.randf() >= _scene_density(kind, layer):
				continue
			var table: PackedStringArray = _scene_table(kind, layer)
			var name: String = table[rng.randi_range(0, table.size() - 1)]
			var jitter: Vector2 = Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
			_place_scene_prop(lib[name], pos + jitter)

## 水面上的睡莲点缀，打散大片纯水
func _sprinkle_lilies(land: PackedByteArray, nx: int, ny: int, rng: RandomNumberGenerator) -> void:
	var lib: Dictionary[String, PropDef] = _scenery_lib()
	for iy: int in ny:
		for ix: int in nx:
			if land[iy * nx + ix] == 1:
				continue
			if rng.randf() >= 0.02:
				continue
			var pos: Vector2 = Vector2((float(ix) + 0.5) * SCENE_CELL, (float(iy) + 0.5) * SCENE_CELL)
			var lilies: PackedStringArray = PackedStringArray(["lily_a", "lily_b", "lily_c"])
			_place_scene_prop(lib[lilies[rng.randi_range(0, lilies.size() - 1)]], pos)

## 弯道地标：外侧一小丛，帮玩家记住"我到哪儿了"
func _spawn_landmark(pos: Vector2, kind: String, rng: RandomNumberGenerator) -> void:
	var lib: Dictionary[String, PropDef] = _scenery_lib()
	var names: PackedStringArray = PackedStringArray(["tree_big", "tree_flower", "tree_small"])
	if kind == "rock":
		names = PackedStringArray(["rock_big", "rock_pile", "rock_dark", "rock_small"])
	elif kind == "meadow":
		names = PackedStringArray(["sunflower", "sunflower", "flower_yellow", "bush_berry"])
	for i: int in 5:
		var offset: Vector2 = Vector2(rng.randf_range(-42.0, 42.0), rng.randf_range(-30.0, 30.0))
		var pick: String = names[rng.randi_range(0, names.size() - 1)]
		_place_scene_prop(lib[pick], pos + offset)

## 木栅栏点缀（纯贴图，无碰撞；封死区靠隐形块挡球）
func _spawn_fence_deco(start: Vector2, count: int) -> void:
	for i: int in count:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _fence_tex
		sprite.region_enabled = true
		var col: int = 1 if i == 0 else (3 if i == count - 1 else 2)
		sprite.region_rect = Rect2(float(col) * 16.0, 48.0, 16.0, 16.0)
		sprite.offset = Vector2(0.0, -8.0)
		sprite.position = start + Vector2(16.0 * float(i), 0.0)
		_world.add_child(sprite)

## 沿中心线按间距摆切线方向箭头（曲线段自动跟着转）
func _spawn_route_arrows(line: RouteLine, spacing: float) -> void:
	if line.points.size() < 2:
		return
	var travelled: float = 0.0
	var next_mark: float = spacing * 0.6
	for i: int in range(line.points.size() - 1):
		var a: Vector2 = line.points[i]
		var b: Vector2 = line.points[i + 1]
		var seg: float = a.distance_to(b)
		if seg < 0.01:
			continue
		if travelled + seg >= next_mark:
			var t: float = (next_mark - travelled) / seg
			_spawn_guide_arrow(a.lerp(b, t), (b - a).normalized())
			next_mark += spacing
		travelled += seg

## 按计划生成整关：光栅化走廊 → 封死外侧 → 铺陆地/水面 → 布景 → 箭头
func _realize_plan(plan: LevelPlan) -> void:
	var nx: int = _island_w
	var ny: int = _island_h
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed

	for gate: GateDef in _gate_defs:
		_add_gate_keepout(gate.position, gate.opening_width)

	var lines: Array[RouteLine] = []
	var spine_line: RouteLine = _sample_plan_line(plan.spine, plan)
	lines.append(spine_line)
	var branch_lines: Array[RouteLine] = []
	for branch: RouteBranch in plan.branches:
		var bl: RouteLine = _sample_plan_line(branch.nodes, plan)
		branch_lines.append(bl)
		lines.append(bl)

	var grid: PackedByteArray = _rasterize_routes(lines, nx, ny)
	_route_grid = grid
	_route_nx = nx
	_route_ny = ny
	var dist: PackedByteArray = _corridor_distance(grid, nx, ny, LAND_BAND_CELLS + 4)
	var shifted_extra: Array[Rect2] = []
	for rect: Rect2 in plan.land_extra:
		shifted_extra.append(Rect2(rect.position + plan.origin, rect.size))
	var shifted_cuts: Array[Rect2] = []
	for rect: Rect2 in plan.water_cuts:
		shifted_cuts.append(Rect2(rect.position + plan.origin, rect.size))
	var land: PackedByteArray = _build_land_mask(
		dist, nx, ny, shifted_extra, shifted_cuts, plan.water_border
	)

	var zones: Array[SceneZone] = []
	for z: SceneZone in plan.zones:
		zones.append(SceneZone.new(Rect2(z.rect.position + plan.origin, z.rect.size), z.kind))

	_seal_from_grid(grid, nx, ny)
	_paint_land(land, grid, dist, nx, ny, zones, rng)
	_decorate_land(land, grid, dist, nx, ny, zones, rng)
	_sprinkle_lilies(land, nx, ny, rng)

	for mark: Dictionary in plan.landmarks:
		_spawn_landmark((mark["pos"] as Vector2) + plan.origin, str(mark["kind"]), rng)
	for fence: Dictionary in plan.fences:
		_spawn_fence_deco((fence["pos"] as Vector2) + plan.origin, int(fence["count"]))

	_spawn_route_arrows(spine_line, plan.arrow_spacing)
	for bl: RouteLine in branch_lines:
		_spawn_route_arrows(bl, plan.arrow_spacing * 0.8)

## 供离线审查工具使用：把计划里某一段路线采样成世界坐标中心线
func sampled_route(plan: LevelPlan, label: String) -> RouteLine:
	if label == "spine":
		return _sample_plan_line(plan.spine, plan)
	for branch: RouteBranch in plan.branches:
		if branch.label == label:
			return _sample_plan_line(branch.nodes, plan)
	return RouteLine.new()

## 供离线审查工具使用：只取路线计划，不建任何节点
func plan_for(level_id: String) -> LevelPlan:
	match level_id:
		"level_1":
			return _plan_level1()
		"level_2":
			return _plan_level2()
		"level_3":
			return _plan_level3()
		"level_4":
			return _plan_level4()
		"level_5":
			return _plan_level5()
	return LevelPlan.new()

## 第 3 关「林间弯道」：四段蜿蜒林道，弯型有缓有紧、有配对。
## 节奏：入林直道（门 1）→ 三连缓弯 → 东侧岩口紧发夹 → 草甸宽恢复
##       → 西侧紧发夹 → 深林窄弯段 → 东侧大半径缓弯 → 花甸收尾（门 2）→ 终点。
## 岛屿 157×121 瓦 = 2512×1936；中心线约 8100px；最窄通道 176px。
func _plan_level3() -> LevelPlan:
	var plan: LevelPlan = LevelPlan.new()
	plan.origin = Vector2(180.0, 120.0)
	plan.island = Vector2i(157, 121)
	plan.arrow_spacing = 330.0
	plan.spine = [
		# 入林直道：门 1 落在 (570,208) 附近，前面留够加速距离
		RouteNode.new(Vector2(150.0, 215.0), 104.0),
		RouteNode.new(Vector2(430.0, 205.0), 100.0),
		RouteNode.new(Vector2(720.0, 220.0), 96.0),
		# 三连缓弯：右—左—右，互为可比较的缓弯组
		RouteNode.new(Vector2(1000.0, 300.0), 96.0, 1.2),
		RouteNode.new(Vector2(1300.0, 280.0), 100.0, 1.2),
		RouteNode.new(Vector2(1620.0, 360.0), 92.0, 1.2),
		RouteNode.new(Vector2(1900.0, 320.0), 96.0, 1.1),
		# 东侧岩口紧发夹：张力放到 0.9，把半径抬到和西侧发夹同档（两者构成"紧右/紧左"配对）
		RouteNode.new(Vector2(2090.0, 470.0), 88.0, 0.9),
		RouteNode.new(Vector2(2010.0, 690.0), 88.0, 0.9),
		# 草甸宽恢复段：难点之后放松
		RouteNode.new(Vector2(1740.0, 760.0), 110.0, 1.1),
		RouteNode.new(Vector2(1440.0, 690.0), 150.0, 1.3),
		RouteNode.new(Vector2(1120.0, 780.0), 150.0, 1.3),
		RouteNode.new(Vector2(800.0, 700.0), 130.0, 1.1),
		RouteNode.new(Vector2(520.0, 780.0), 96.0, 1.1),
		# 西侧紧发夹：节点几何按东侧发夹左右镜像（同样的入弯距离、外凸量、张力），
		# 这样左右两个紧弯半径接近，才能当成可比较的"紧左/紧右"配对
		RouteNode.new(Vector2(375.0, 935.0), 88.0, 0.7),
		RouteNode.new(Vector2(455.0, 1145.0), 88.0, 0.7),
		# 深林窄弯段：连续中速弯，通道收到最窄
		RouteNode.new(Vector2(680.0, 1200.0), 110.0, 1.1),
		RouteNode.new(Vector2(1020.0, 1150.0), 90.0, 1.2),
		RouteNode.new(Vector2(1340.0, 1210.0), 88.0, 1.2),
		RouteNode.new(Vector2(1680.0, 1150.0), 96.0, 1.1),
		# 东侧大半径缓弯（比发夹缓很多，形成难度落差）
		RouteNode.new(Vector2(1980.0, 1230.0), 100.0, 0.9),
		RouteNode.new(Vector2(2010.0, 1420.0), 110.0, 0.9),
		# 花甸收尾：门 2 落在 (860,1510) 附近
		RouteNode.new(Vector2(1700.0, 1480.0), 120.0, 1.1),
		RouteNode.new(Vector2(1350.0, 1540.0), 130.0, 1.2),
		RouteNode.new(Vector2(1000.0, 1490.0), 110.0, 1.2),
		RouteNode.new(Vector2(700.0, 1530.0), 104.0),
		RouteNode.new(Vector2(400.0, 1500.0), 100.0),
		RouteNode.new(Vector2(170.0, 1540.0), 110.0),
	]
	plan.zones = [
		SceneZone.new(Rect2(1760.0, 360.0, 500.0, 460.0), "rock"),
		SceneZone.new(Rect2(860.0, 540.0, 780.0, 360.0), "meadow"),
		SceneZone.new(Rect2(160.0, 860.0, 340.0, 360.0), "rock"),
		SceneZone.new(Rect2(560.0, 1020.0, 1240.0, 320.0), "deep_forest"),
		SceneZone.new(Rect2(1000.0, 1380.0, 700.0, 300.0), "meadow"),
	]
	plan.water_cuts = [
		Rect2(220.0, 380.0, 540.0, 260.0),
		Rect2(180.0, 1250.0, 360.0, 200.0),
		Rect2(1780.0, 900.0, 460.0, 180.0),
	]
	plan.land_extra = [
		Rect2(2270.0, 720.0, 190.0, 170.0),
		Rect2(40.0, 560.0, 150.0, 150.0),
	]
	plan.landmarks = [
		{"pos": Vector2(2160.0, 580.0), "kind": "rock"},
		{"pos": Vector2(230.0, 1040.0), "kind": "rock"},
		{"pos": Vector2(1160.0, 910.0), "kind": "meadow"},
		{"pos": Vector2(1340.0, 1660.0), "kind": "meadow"},
		{"pos": Vector2(880.0, 380.0), "kind": "forest"},
	]
	plan.fences = [
		{"pos": Vector2(1180.0, 560.0), "count": 9},
		{"pos": Vector2(1080.0, 1660.0), "count": 8},
	]
	return plan

func _build_level3_layout() -> void:
	_realize_plan(_plan_level3())

## 第 4 关「宽路失衡」：全程宽阔缓弯大道，没有窄井、没有门、没有分叉。
## 三个候选扰动段各自风貌不同（湖畔直道 / 林间缓弯 / 草甸广场旁），间隔不规则。
## 岛屿 153×122 瓦 = 2448×1952；中心线约 7400px；最窄通道 250px。
func _plan_level4() -> LevelPlan:
	var plan: LevelPlan = LevelPlan.new()
	plan.origin = Vector2(200.0, 120.0)
	plan.island = Vector2i(153, 122)
	plan.arrow_spacing = 420.0
	plan.spine = [
		# 湖畔起步大道（候选扰动段 A）
		RouteNode.new(Vector2(150.0, 240.0), 140.0),
		RouteNode.new(Vector2(520.0, 235.0), 145.0),
		RouteNode.new(Vector2(900.0, 270.0), 150.0),
		RouteNode.new(Vector2(1300.0, 250.0), 143.0, 1.2),
		RouteNode.new(Vector2(1680.0, 310.0), 132.0, 1.2),
		# 东侧大半径缓弯
		RouteNode.new(Vector2(1960.0, 440.0), 125.0, 0.85),
		RouteNode.new(Vector2(1900.0, 650.0), 130.0, 0.85),
		# 林间缓弯（候选扰动段 B）→ 草甸广场（全关最宽）
		RouteNode.new(Vector2(1560.0, 710.0), 150.0, 1.2),
		RouteNode.new(Vector2(1180.0, 660.0), 165.0, 1.3),
		RouteNode.new(Vector2(820.0, 720.0), 175.0, 1.3),
		RouteNode.new(Vector2(480.0, 670.0), 150.0, 1.1),
		# 西侧大半径缓弯
		RouteNode.new(Vector2(260.0, 850.0), 130.0, 0.85),
		RouteNode.new(Vector2(380.0, 1080.0), 130.0, 0.9),
		# 长缓 S（候选扰动段 C 在西段）
		RouteNode.new(Vector2(760.0, 1140.0), 140.0, 1.2),
		RouteNode.new(Vector2(1150.0, 1070.0), 150.0, 1.2),
		RouteNode.new(Vector2(1520.0, 1140.0), 140.0, 1.2),
		RouteNode.new(Vector2(1860.0, 1240.0), 125.0, 0.85),
		RouteNode.new(Vector2(1900.0, 1440.0), 130.0, 0.9),
		# 收尾大道回到西侧终点
		RouteNode.new(Vector2(1560.0, 1520.0), 150.0, 1.2),
		RouteNode.new(Vector2(1150.0, 1470.0), 160.0, 1.2),
		RouteNode.new(Vector2(760.0, 1540.0), 150.0, 1.1),
		RouteNode.new(Vector2(400.0, 1490.0), 140.0),
		RouteNode.new(Vector2(170.0, 1530.0), 150.0),
	]
	plan.zones = [
		SceneZone.new(Rect2(1780.0, 380.0, 440.0, 420.0), "rock"),
		SceneZone.new(Rect2(460.0, 540.0, 960.0, 340.0), "meadow"),
		SceneZone.new(Rect2(860.0, 980.0, 760.0, 300.0), "deep_forest"),
		SceneZone.new(Rect2(640.0, 1400.0, 780.0, 300.0), "meadow"),
	]
	plan.water_cuts = [
		Rect2(520.0, 400.0, 760.0, 170.0),
		Rect2(1480.0, 880.0, 600.0, 180.0),
		Rect2(220.0, 1220.0, 320.0, 190.0),
		Rect2(1560.0, 1280.0, 420.0, 150.0),
	]
	plan.land_extra = [
		Rect2(2300.0, 680.0, 180.0, 200.0),
		Rect2(40.0, 380.0, 160.0, 160.0),
	]
	plan.landmarks = [
		{"pos": Vector2(1020.0, 900.0), "kind": "meadow"},
		{"pos": Vector2(2060.0, 560.0), "kind": "rock"},
		{"pos": Vector2(1280.0, 1320.0), "kind": "forest"},
		{"pos": Vector2(520.0, 1680.0), "kind": "meadow"},
		{"pos": Vector2(300.0, 1020.0), "kind": "rock"},
	]
	plan.fences = [
		{"pos": Vector2(900.0, 900.0), "count": 11},
		{"pos": Vector2(760.0, 1700.0), "count": 9},
	]
	return plan

func _build_level4_layout() -> void:
	_realize_plan(_plan_level4())

## 第 5 关「双岔路」：出生 → 岔路 1（北窄短 / 南宽长）→ 汇合长路 + 一扇门
## → 岔路 2（方向对调：北宽长 / 南窄短）→ 收尾 → 终点。
## 两个岔路的风貌不同：岔 1 是岩石窄道对草甸宽道，岔 2 是草甸宽道对深林窄道。
## 岔路中间各留一片湖，让"两条路"在视觉上真的分开。
## 岛屿 178×124 瓦 = 2848×1984；安全（宽）路线约 7600px。
func _plan_level5() -> LevelPlan:
	var plan: LevelPlan = LevelPlan.new()
	plan.origin = Vector2(180.0, 140.0)
	plan.island = Vector2i(178, 124)
	plan.arrow_spacing = 340.0
	plan.centerline_order = PackedStringArray([
		"spine", "fork1_wide", "spine_b", "fork2_wide", "spine_c",
	])
	# 导入段：缓弯把人送到岔路 1，入口前留足观察距离
	plan.spine = [
		RouteNode.new(Vector2(150.0, 230.0), 96.0),
		RouteNode.new(Vector2(430.0, 220.0), 96.0),
		RouteNode.new(Vector2(720.0, 280.0), 92.0, 1.2),
		RouteNode.new(Vector2(980.0, 250.0), 96.0, 1.1),
		RouteNode.new(Vector2(1180.0, 330.0), 100.0, 0.95),
		RouteNode.new(Vector2(1300.0, 400.0), 104.0, 0.9),
	]
	plan.branches = [
		# 岔 1 北支：短且窄，两侧岩石，看起来更险
		RouteBranch.new([
			RouteNode.new(Vector2(1300.0, 400.0), 104.0, 0.9),
			RouteNode.new(Vector2(1450.0, 250.0), 88.0, 1.1),
			RouteNode.new(Vector2(1750.0, 205.0), 86.0, 1.2),
			RouteNode.new(Vector2(2020.0, 265.0), 86.0, 1.1),
			RouteNode.new(Vector2(2150.0, 430.0), 104.0, 0.9),
		], "fork1_narrow"),
		# 岔 1 南支：长且宽，穿草甸，安全但绕
		RouteBranch.new([
			RouteNode.new(Vector2(1300.0, 400.0), 104.0, 0.9),
			RouteNode.new(Vector2(1420.0, 700.0), 125.0, 1.1),
			RouteNode.new(Vector2(1700.0, 860.0), 132.0, 1.2),
			RouteNode.new(Vector2(1980.0, 820.0), 132.0, 1.2),
			RouteNode.new(Vector2(2100.0, 620.0), 120.0, 1.0),
			RouteNode.new(Vector2(2150.0, 430.0), 104.0, 0.9),
		], "fork1_wide"),
		# 汇合长路：沿东缘南下再西行，中段一扇门
		RouteBranch.new([
			RouteNode.new(Vector2(2150.0, 430.0), 104.0, 0.9),
			RouteNode.new(Vector2(2380.0, 560.0), 100.0, 0.9),
			RouteNode.new(Vector2(2400.0, 860.0), 100.0, 0.9),
			RouteNode.new(Vector2(2100.0, 1000.0), 108.0, 1.2),
			RouteNode.new(Vector2(1700.0, 950.0), 106.0, 1.2),
			RouteNode.new(Vector2(1450.0, 1020.0), 92.0, 1.0),
			RouteNode.new(Vector2(1300.0, 1080.0), 100.0, 0.9),
		], "spine_b"),
		# 岔 2 北支：这次宽长在北（与岔 1 对调），穿草甸
		RouteBranch.new([
			RouteNode.new(Vector2(1300.0, 1080.0), 100.0, 0.9),
			RouteNode.new(Vector2(1150.0, 800.0), 125.0, 1.1),
			RouteNode.new(Vector2(850.0, 720.0), 132.0, 1.2),
			RouteNode.new(Vector2(560.0, 800.0), 132.0, 1.1),
			RouteNode.new(Vector2(430.0, 1000.0), 120.0, 1.0),
			RouteNode.new(Vector2(450.0, 1150.0), 100.0, 0.9),
		], "fork2_wide"),
		# 岔 2 南支：窄短在南，穿深林
		RouteBranch.new([
			RouteNode.new(Vector2(1300.0, 1080.0), 100.0, 0.9),
			RouteNode.new(Vector2(1100.0, 1240.0), 88.0, 1.1),
			RouteNode.new(Vector2(800.0, 1280.0), 86.0, 1.2),
			RouteNode.new(Vector2(560.0, 1230.0), 86.0, 1.1),
			RouteNode.new(Vector2(450.0, 1150.0), 100.0, 0.9),
		], "fork2_narrow"),
		# 收尾段：沿南缘东行到终点
		RouteBranch.new([
			RouteNode.new(Vector2(450.0, 1150.0), 100.0, 0.9),
			RouteNode.new(Vector2(430.0, 1420.0), 96.0, 0.9),
			RouteNode.new(Vector2(700.0, 1560.0), 100.0, 1.1),
			RouteNode.new(Vector2(1050.0, 1580.0), 104.0, 1.2),
			RouteNode.new(Vector2(1400.0, 1540.0), 100.0, 1.2),
			RouteNode.new(Vector2(1750.0, 1590.0), 104.0, 1.1),
			RouteNode.new(Vector2(2100.0, 1550.0), 110.0),
			RouteNode.new(Vector2(2400.0, 1520.0), 120.0),
		], "spine_c"),
	]
	plan.zones = [
		SceneZone.new(Rect2(1340.0, 120.0, 800.0, 260.0), "rock"),
		SceneZone.new(Rect2(1360.0, 660.0, 800.0, 320.0), "meadow"),
		SceneZone.new(Rect2(2180.0, 480.0, 300.0, 520.0), "rock"),
		SceneZone.new(Rect2(480.0, 620.0, 880.0, 320.0), "meadow"),
		SceneZone.new(Rect2(460.0, 1160.0, 900.0, 260.0), "deep_forest"),
	]
	plan.water_cuts = [
		Rect2(1450.0, 420.0, 620.0, 140.0),
		Rect2(620.0, 990.0, 500.0, 150.0),
		Rect2(250.0, 420.0, 560.0, 130.0),
		Rect2(1500.0, 1180.0, 620.0, 200.0),
	]
	plan.land_extra = [
		Rect2(2520.0, 900.0, 190.0, 200.0),
		Rect2(40.0, 700.0, 150.0, 200.0),
	]
	plan.landmarks = [
		{"pos": Vector2(1740.0, 110.0), "kind": "rock"},
		{"pos": Vector2(1700.0, 700.0), "kind": "meadow"},
		{"pos": Vector2(900.0, 620.0), "kind": "meadow"},
		{"pos": Vector2(860.0, 1420.0), "kind": "forest"},
		{"pos": Vector2(2480.0, 700.0), "kind": "rock"},
		{"pos": Vector2(1240.0, 1720.0), "kind": "meadow"},
	]
	plan.fences = [
		{"pos": Vector2(700.0, 620.0), "count": 11},
		{"pos": Vector2(1520.0, 560.0), "count": 8},
	]
	return plan

func _build_level5_layout() -> void:
	_realize_plan(_plan_level5())

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
	body.add_to_group("ordinary_obstacle")
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
	body.add_to_group("world_boundary")
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.position = rect.get_center()
	body.add_child(shape)
	_world.add_child(body)
