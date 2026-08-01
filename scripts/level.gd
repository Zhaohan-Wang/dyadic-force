extends Node2D
## 通用关卡运行时：建岛、分屏、计时、血量、终点、重生与教程推进。

@export var fallback_level: LevelDef  # 直接运行本场景时使用的关卡

@onready var _water_layer: TileMapLayer = $WaterLayer
@onready var _ground_layer: TileMapLayer = $GroundLayer
@onready var _decor_layer: TileMapLayer = $DecorLayer
@onready var _world: Node2D = $World
@onready var _ball: PixelBall = $World/Ball
@onready var _split_screen: SplitScreen = $SplitScreen

var _def: LevelDef
var _state: LevelState
var _builder: WorldBuilder
var _health: BallHealth
var _goal: GoalArea
var _hud: LevelHud
var _respawning: bool = false
## 教程推进用：记录已触发的步骤条件
var _tut_flags: Dictionary = {}

func _ready() -> void:
	_def = GameState.current_level
	if _def == null:
		_def = fallback_level
	if _def == null:
		push_error("Level: 没有 LevelDef，无法启动")
		return

	# 开发兜底：编辑器里直接跑本场景（没走配对流程）时补默认键盘；
	# 正常流程玩家必须在配对界面主动加入，不会触发这里。
	if GameState.current_level == null and not InputHub.both_ready():
		InputHub.debug_assign_defaults()

	InputHub.input_frozen = false
	_state = LevelState.new()
	_state.setup(_def)

	_builder = WorldBuilder.new()
	_builder.bind(_water_layer, _ground_layer, _decor_layer, _world)
	_builder.build(_def)

	# 球放到出生点
	_ball.global_position = _def.spawn_point
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0

	_spawn_spawn_marker()
	_spawn_goal()
	_setup_health()
	_setup_hud()

	var island_px: Vector2i = _builder.island_size_px()
	_split_screen.island_w_px = island_px.x
	_split_screen.island_h_px = island_px.y
	var world_nodes: Array[Node] = [_water_layer, _ground_layer, _decor_layer, _world]
	_split_screen.activate(
		world_nodes,
		_ball.get_node("Monkey1") as Node2D,
		_ball.get_node("Monkey2") as Node2D,
		_ball
	)

	_state.ensure_tutorial_started()
	_state.phase_changed.connect(_on_phase_changed)

func _physics_process(delta: float) -> void:
	if _state == null:
		return
	# 第一次有输入 → 开始计时
	if _state.phase == LevelState.Phase.READY:
		var any_input: bool = InputHub.get_move_vector(0) != Vector2.ZERO \
			or InputHub.get_move_vector(1) != Vector2.ZERO
		if any_input:
			_state.start_running()

	if _state.phase == LevelState.Phase.RUNNING:
		if _state.tick_time(delta):
			_on_failed()
		_update_tutorial_progress()

## 出生点视觉标记（浅色圆盘）
func _spawn_spawn_marker() -> void:
	var marker: Node2D = Node2D.new()
	marker.name = "SpawnMarker"
	marker.position = _def.spawn_point
	var sprite: Sprite2D = Sprite2D.new()
	var img: Image = Image.create(28, 28, false, Image.FORMAT_RGBA8)
	for y: int in 28:
		for x: int in 28:
			var dx: float = float(x) - 13.5
			var dy: float = float(y) - 13.5
			var d: float = sqrt(dx * dx + dy * dy)
			if d < 12.0 and d > 9.0:
				img.set_pixel(x, y, Color(0.55, 0.78, 0.95, 0.5))
			elif d <= 9.0:
				img.set_pixel(x, y, Color(0.55, 0.78, 0.95, 0.15))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.z_index = -2
	marker.add_child(sprite)
	_world.add_child(marker)

func _spawn_goal() -> void:
	_goal = GoalArea.new()
	_goal.name = "Goal"
	_goal.position = _def.goal_point
	_world.add_child(_goal)
	_goal.reached.connect(_on_goal_reached)

func _setup_health() -> void:
	_health = BallHealth.new()
	_health.name = "BallHealth"
	_ball.add_child(_health)
	_health.setup(_ball, _state)
	_health.died.connect(_on_ball_died)
	_health.damaged.connect(_on_ball_damaged)

func _setup_hud() -> void:
	_hud = LevelHud.new()
	_hud.name = "LevelHud"
	add_child(_hud)
	_hud.setup(_state, _def.level_name)

func _on_ball_damaged(_amount: float, _hp: float) -> void:
	_split_screen.shake(180.0)

func _on_ball_died() -> void:
	if _respawning or _state.phase == LevelState.Phase.FINISHED:
		return
	_respawning = true
	_state.enter_dead()
	InputHub.input_frozen = true
	await _respawn_sequence()

## 死亡 → 爆炸 → 相机回出生点 → 闪白重生（参考 Celeste / Mario）
func _respawn_sequence() -> void:
	var death_pos: Vector2 = _ball.global_position

	# 1) 撞烂：爆炸 + 顿帧 + 重震屏，球立刻消失冻住
	BallBurst.play(_world, death_pos)
	_health.clear_visuals()
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0
	_ball.freeze = true
	_ball.visible = false

	# 顿帧（hitstop）：世界慢放一瞬，强化撞碎冲击感
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.09, true, false, true).timeout
	Engine.time_scale = 1.0
	_split_screen.death_shake()

	# 让玩家看清爆炸
	await get_tree().create_timer(0.45).timeout

	# 2) 两侧相机锁定并挪到出生点
	_split_screen.lock_cameras(_def.spawn_point)
	await get_tree().create_timer(0.55).timeout

	# 3) 球放到出生点（仍隐藏），正式关扣时
	_ball.global_position = _def.spawn_point
	_ball.rotation = 0.0
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0
	if not _def.is_practice:
		_state.apply_time_penalty(_def.death_time_penalty)

	# 4) 出现：满血 + 闪白 + 无敌闪烁，再交还操作
	_ball.visible = true
	_ball.freeze = false
	_ball.modulate = Color.WHITE
	_state.revive()
	_health.begin_spawn_protection()
	_split_screen.unlock_cameras()
	_split_screen.shake(90.0)

	await get_tree().create_timer(0.2).timeout
	InputHub.input_frozen = false
	_respawning = false

func _on_goal_reached() -> void:
	if _state.phase != LevelState.Phase.RUNNING and _state.phase != LevelState.Phase.READY:
		return
	InputHub.input_frozen = true
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0
	var ratio: float = 0.0 if _state.max_hp <= 0.0 else _state.hp / _state.max_hp
	_state.finish(ratio)
	GameState.mark_cleared(_def.level_id)
	GameState.last_result = {
		"level_id": _def.level_id,
		"level_name": _def.level_name,
		"elapsed": _state.elapsed,
		"time_left": _state.time_left,
		"timed": _state.timed,
		"hp": _state.hp,
		"max_hp": _state.max_hp,
		"stars": _state.stars,
		"success": true,
	}
	await get_tree().create_timer(0.6).timeout
	SceneDirector.go_to("res://scenes/results_screen.tscn")

func _on_failed() -> void:
	InputHub.input_frozen = true
	GameState.last_result = {
		"level_id": _def.level_id,
		"level_name": _def.level_name,
		"elapsed": _state.elapsed,
		"time_left": 0.0,
		"timed": true,
		"hp": _state.hp,
		"max_hp": _state.max_hp,
		"stars": 0,
		"success": false,
	}
	await get_tree().create_timer(0.5).timeout
	SceneDirector.go_to("res://scenes/results_screen.tscn")

func _on_phase_changed(_phase: LevelState.Phase) -> void:
	pass

## 根据玩家行为推进练习关教程
func _update_tutorial_progress() -> void:
	if _def.tutorial_steps.is_empty():
		return
	var step: int = _state.tutorial_step
	var v1: Vector2 = InputHub.get_move_vector(0)
	var v2: Vector2 = InputHub.get_move_vector(1)
	# 0: 同向推
	if step == 0 and v1 != Vector2.ZERO and v2 != Vector2.ZERO:
		if v1.dot(v2) > 0.5:
			_tut_flags["same"] = true
	if step == 0 and _tut_flags.get("same", false) and _ball.linear_velocity.length() > 40.0:
		_state.advance_tutorial()
	# 1: 反向旋转
	elif step == 1 and v1 != Vector2.ZERO and v2 != Vector2.ZERO:
		if v1.dot(v2) < -0.3 and absf(_ball.angular_velocity) > 1.0:
			_state.advance_tutorial()
	# 2: 撞击掉血（有过扣血即可）
	elif step == 2 and _state.hp < _state.max_hp - 0.5:
		_state.advance_tutorial()
	# 3: 到达终点附近
	elif step == 3:
		if _ball.global_position.distance_to(_def.goal_point) < 120.0:
			_state.advance_tutorial()
