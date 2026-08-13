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
## 第 2、3 关共用 gauntlet；第 4、5 关为加长的独立作者图。
func _build_authored_layout() -> void:
	match _level_id:
		"level_1":
			_build_level1_layout()
		"level_2", "level_3":
			_build_gauntlet_layout()
		"level_4":
			_build_level4_layout()
		"level_5":
			_build_level5_layout()
		_:
			_spawn_obstacles()

## 第 1 关（1120x416）：八道闸门蛇形缓弯，路线长度对齐第 2/3 关量级。
## 球 R=44；上闸从下过，下闸从上过；窄缝球心带约 50px。
func _build_level1_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	var trees: Array[PropDef] = _tree_defs()
	var rocks: Array[PropDef] = _rock_defs()

	# 闸 1 上 → 从下过
	for cy: float in [56.0, 98.0, 140.0, 180.0]:
		_world.add_child(_make_prop(trees[1], Vector2(170.0, cy)))
	# 闸 2 下 → 从上过
	for cy: float in [380.0, 348.0, 316.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(300.0, cy)))
	_world.add_child(_make_prop(rocks[1], Vector2(318.0, 360.0)))
	# 闸 3 上
	for cy: float in [56.0, 98.0, 140.0, 180.0]:
		_world.add_child(_make_prop(trees[0], Vector2(430.0, cy)))
	# 闸 4 窄缝（中心约 y=220）
	for cy: float in [56.0, 90.0, 124.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(560.0, cy)))
	for cy: float in [330.0, 364.0, 398.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(560.0, cy)))
	# 闸 5 上
	for cy: float in [56.0, 98.0, 140.0, 180.0]:
		_world.add_child(_make_prop(trees[1], Vector2(690.0, cy)))
	# 闸 6 下
	for cy: float in [380.0, 348.0, 316.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(820.0, cy)))
	# 闸 7 上
	for cy: float in [56.0, 98.0, 140.0, 180.0]:
		_world.add_child(_make_prop(trees[0], Vector2(940.0, cy)))
	# 闸 8 窄缝收尾
	for cy: float in [56.0, 90.0, 124.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(1040.0, cy)))
	for cy: float in [330.0, 364.0, 398.0]:
		_world.add_child(_make_prop(rocks[0], Vector2(1040.0, cy)))

	_spawn_guide_arrow(Vector2(110.0, 280.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(170.0, 290.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(300.0, 200.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(430.0, 290.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(560.0, 220.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(690.0, 290.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(820.0, 200.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(940.0, 290.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(1040.0, 220.0), Vector2.RIGHT)

	_spawn_corner_trees(w, h)
	_sprinkle_decor(7)

## 第 2/3 关共用图（1056x544）：强制底廊 + 窄井 + 高跑扁管 + 短墙下压 + 树丛绕行 + 烟囱。
## 硬约束（球 R=44；灌木 r=8.5，圆心=放置点+(0,-r)）：
##   - 水平扁管放置间距 ≥ 120px（球心带 ≥ 15px）；管内禁止居中石；
##   - 垂直井两墙间距 ≥ 145px（球心带 ≥ 40px）；井内禁止障碍；
##   - 改完必须跑 tools/gauntlet_reachability_assert.gd。
func _build_gauntlet_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	var rocks: Array[PropDef] = _rock_defs()
	var bushes: Array[PropDef] = _bush_defs()
	var trees: Array[PropDef] = _tree_defs()

	# ---- 1) 封死左半场中路：只能走底廊 ----
	_spawn_bush_line(Vector2(48.0, 300.0), Vector2(14.0, 0.0), 12)  # 中路横墙
	_world.add_child(_make_prop(trees[0], Vector2(100.0, 180.0)))
	_world.add_child(_make_prop(trees[1], Vector2(160.0, 220.0)))

	# ---- 2) 开局底廊（间距 130px，球心带约 25px）----
	_spawn_bush_line(Vector2(48.0, 360.0), Vector2(14.0, 0.0), 13)  # 廊顶
	_spawn_bush_line(Vector2(48.0, 490.0), Vector2(14.0, 0.0), 13)  # 廊底
	# 只贴边咬口，中线可过
	_world.add_child(_make_prop(rocks[1], Vector2(130.0, 372.0)))
	_world.add_child(_make_prop(rocks[1], Vector2(180.0, 478.0)))

	# ---- 3) T1 闸：加长 + 贴底石，底缝球心带约 18px ----
	_spawn_bush_line(Vector2(250.0, 36.0), Vector2(0.0, 13.0), 26)  # 尖端 y≈361
	_world.add_child(_make_prop(rocks[0], Vector2(250.0, 478.0)))

	# ---- 4) B1 闸：距 T1=145px → 球心井宽约 40px；井内空 ----
	_spawn_bush_line(Vector2(395.0, h - 20.0), Vector2(0.0, -13.0), 23)  # 尖端 y≈238

	# ---- 5) 翻 B1 后的高跑扁管（间距 125px）；地板短于天花，右侧留下潜口 ----
	_spawn_bush_line(Vector2(420.0, 48.0), Vector2(14.0, 0.0), 11)   # 天花 → x≈560
	_spawn_bush_line(Vector2(420.0, 173.0), Vector2(14.0, 0.0), 8)   # 地板 → x≈518，先结束
	# 贴边石只放在扁管中前段，远离出口
	_world.add_child(_make_prop(rocks[1], Vector2(460.0, 60.0)))
	_world.add_child(_make_prop(rocks[1], Vector2(490.0, 161.0)))

	# ---- 6) 短墙下压：出扁管后下潜钻过（尖端 y≈140 → 球心 y≥184）----
	# 与扁管出口拉开间距，保证有下潜转弯空间
	_spawn_bush_line(Vector2(630.0, 36.0), Vector2(0.0, 13.0), 9)

	# ---- 7) 树丛 + B2：封死下方抄近路，逼从顶/右缘绕 ----
	_spawn_bush_line(Vector2(720.0, h - 20.0), Vector2(0.0, -13.0), 12)
	_world.add_child(_make_prop(bushes[0], Vector2(675.0, 360.0)))
	_world.add_child(_make_prop(bushes[1], Vector2(765.0, 360.0)))
	var cx: float = 720.0
	var cy: float = 268.0
	_world.add_child(_make_prop(trees[1], Vector2(cx, cy + 12.0)))
	for i: int in 6:
		var ang: float = TAU / 6.0 * float(i)
		var pos: Vector2 = Vector2(cx + 52.0 * cos(ang), cy + 52.0 * sin(ang) + 12.0)
		_world.add_child(_make_prop(trees[i % 2], pos))
	# 挡扁管出口直冲树丛下方的抄近路（放在短墙右侧、下潜通道下方）
	_world.add_child(_make_prop(rocks[0], Vector2(650.0, 280.0)))

	# ---- 8) 右下沉底闸 C1（从下往上，球从其顶翻过）：避免与 T2 双顶墙夹死 ----
	_spawn_bush_line(Vector2(840.0, h - 20.0), Vector2(0.0, -13.0), 14)  # 尖端 y≈342
	_world.add_child(_make_prop(rocks[1], Vector2(840.0, 310.0)))  # 顶端再压一点

	# ---- 9) T2 烟囱：贴右爬升（T2≤950）----
	_spawn_bush_line(Vector2(930.0, 36.0), Vector2(0.0, 13.0), 18)  # 尖端 y≈257
	_world.add_child(_make_prop(rocks[0], Vector2(930.0, 448.0)))

	_spawn_guide_arrow(Vector2(120.0, 425.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(250.0, 412.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(320.0, 300.0), Vector2.UP)
	_spawn_guide_arrow(Vector2(500.0, 110.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(580.0, 200.0), Vector2.DOWN)
	_spawn_guide_arrow(Vector2(720.0, 130.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(800.0, 280.0), Vector2.DOWN)
	_spawn_guide_arrow(Vector2(840.0, 250.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(980.0, 360.0), Vector2.UP)

	_spawn_corner_trees(w, h)
	_sprinkle_decor(8)

## 第 4 关：三层宽阔折返场。
## 两堵横墙分别在右侧、左侧留出大开口，形成「右行—左行—右行」的大回头体验。
## 每层球心可活动高度约 96px；两处回转区的球心宽度均超过 150px。
func _build_level4_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	# 下层隔墙：左端封住，右侧保留约 160px 的宽回转区。
	_spawn_bush_line(Vector2(40.0, 440.0), Vector2(14.0, 0.0), 63)
	# 上层隔墙：右端封住，左侧保留约 155px 的宽回转区。
	_spawn_bush_line(Vector2(260.0, 240.0), Vector2(14.0, 0.0), 58)

	# 下层：一路向右，到墙尾做第一次 180° 回头。
	_spawn_guide_arrow(Vector2(150.0, 540.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(480.0, 540.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(850.0, 540.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(1000.0, 390.0), Vector2.UP)
	# 中层：向左横穿，在左端做第二次 180° 回头。
	_spawn_guide_arrow(Vector2(850.0, 340.0), Vector2.LEFT)
	_spawn_guide_arrow(Vector2(520.0, 340.0), Vector2.LEFT)
	_spawn_guide_arrow(Vector2(190.0, 340.0), Vector2.LEFT)
	_spawn_guide_arrow(Vector2(140.0, 190.0), Vector2.UP)
	# 上层：向右冲向终点。
	_spawn_guide_arrow(Vector2(330.0, 130.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(680.0, 130.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(980.0, 130.0), Vector2.RIGHT)

	_spawn_corner_trees(w, h)
	_sprinkle_decor(8)

## 第 5 关：矩形螺旋。
## 六段灌木墙首尾交错连接，玩家从外圈顺时针绕入中心；不存在第 2/3 关的窄井/高架。
## 最窄的强制通道按球心仍留约 65px，回转区更宽。
func _build_level5_layout() -> void:
	var w: float = float(_island_w * TILE_SIZE)
	var h: float = float(_island_h * TILE_SIZE)
	_spawn_fence_row(Vector2(32.0, 20.0), int((w - 64.0) / 16.0))
	_spawn_fence_row(Vector2(32.0, h - 10.0), int((w - 64.0) / 16.0))

	var trees: Array[PropDef] = _tree_defs()

	# 外圈下墙 + 右墙：迫使开局先向右，再沿地图右缘向上。
	_spawn_bush_line(Vector2(40.0, 530.0), Vector2(14.0, 0.0), 51)   # 末端 x=740
	_spawn_bush_line(Vector2(740.0, 530.0), Vector2(0.0, -13.0), 29) # 末端 y≈166
	# 外圈上墙 + 左墙：到顶后向左，再沿左侧向下进入内圈。
	_spawn_bush_line(Vector2(180.0, 160.0), Vector2(14.0, 0.0), 41)  # 末端 x=740
	_spawn_bush_line(Vector2(180.0, 160.0), Vector2(0.0, 13.0), 10)  # 末端 y≈277
	# 内圈下墙 + 右墙：从左侧转向右，再从右侧向上切入中心。
	_spawn_bush_line(Vector2(180.0, 440.0), Vector2(14.0, 0.0), 27)  # 末端 x≈544
	_spawn_bush_line(Vector2(548.0, 440.0), Vector2(0.0, -13.0), 10) # 末端 y≈323

	# 中央树作为视觉锚点；位置在终点左上，不侵占最后一段进场路线。
	_world.add_child(_make_prop(trees[1], Vector2(350.0, 300.0)))
	_world.add_child(_make_prop(trees[2], Vector2(390.0, 285.0)))

	# 外圈顺时针。
	_spawn_guide_arrow(Vector2(140.0, 610.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(420.0, 610.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(820.0, 610.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(850.0, 420.0), Vector2.UP)
	_spawn_guide_arrow(Vector2(850.0, 220.0), Vector2.UP)
	_spawn_guide_arrow(Vector2(520.0, 90.0), Vector2.LEFT)
	_spawn_guide_arrow(Vector2(250.0, 90.0), Vector2.LEFT)
	_spawn_guide_arrow(Vector2(105.0, 250.0), Vector2.DOWN)
	# 内圈逆向折入中心。
	_spawn_guide_arrow(Vector2(105.0, 390.0), Vector2.DOWN)
	_spawn_guide_arrow(Vector2(300.0, 350.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(430.0, 350.0), Vector2.RIGHT)
	_spawn_guide_arrow(Vector2(480.0, 300.0), Vector2.UP)

	_spawn_corner_trees(w, h)
	_sprinkle_decor(8)

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
