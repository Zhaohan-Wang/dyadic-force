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
var _physics_debug: PhysicsDebugPanel
var _respawning: bool = false
## 教程推进用：记录已触发的步骤条件
var _tut_flags: Dictionary = {}
## 结算轨迹：当前这一命的采样（通关时即成功路线）
var _trail: PackedVector2Array = PackedVector2Array()
var _trail_timer: float = 0.0
## 死亡/重置前的失败路线（结算图画虚线）
var _failed_trails: Array[PackedVector2Array] = []
## 每次扣血时球的位置（结算图上标红点）
var _hit_points: PackedVector2Array = PackedVector2Array()
## 真实扰动生效期间走过的路径（结算图上高亮成"偏移区间"）
var _perturb_spans: Array[PackedVector2Array] = []
## 当前是否处于真实扰动中
var _perturb_active: bool = false
## 本局真实扰动累计时长（秒）
var _perturb_seconds: float = 0.0

## ---- 开场须知弹窗 ----
## 弹窗所在层（非 null = 弹窗展示中，输入冻结、任意键关闭）
var _intro_layer: CanvasLayer = null
## 关卡内暂停菜单
var _pause_menu: PauseMenu = null
var _trial_closed: bool = false

## ---- 五关扩展组件 ----
var _gates: Array[BreakableGate] = []
var _segment_zones: Array[RouteSegmentZone] = []
var _perturb: PerturbationController = PerturbationController.new()
var _choice_tracker: ChoiceForkTracker = ChoiceForkTracker.new()
var _active_segment_id: String = ""
var _active_segment_type: String = ""
var _active_gate_id: String = ""

func _ready() -> void:
	# 进入关卡先收掉菜单音乐；玩家首次推动球后再启动关卡音乐。
	AudioHub.stop_music()
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
	InputHub.reset_gains()
	_state = LevelState.new()
	_state.setup(_def)

	_builder = WorldBuilder.new()
	_builder.bind(_water_layer, _ground_layer, _decor_layer, _world)
	_builder.build(_def)

	# 球放到出生点
	_ball.global_position = _def.spawn_point
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0
	# 调试调参（若有本地文件）在开局统一套到球上。
	PhysicsTuning.apply_to_ball(_ball)

	_spawn_spawn_marker()
	_spawn_goal()
	_setup_health()
	_setup_challenge_components()
	_setup_hud()
	_setup_physics_debug()
	_setup_pause_menu()

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
	HapticHub.begin_level(_health)

	_state.ensure_tutorial_started()
	_state.phase_changed.connect(_on_phase_changed)
	# 开局即建立不可覆盖 trial（含 READY 阶段输入）。
	if not ExperimentLog.begin_trial(_def):
		push_error("Level: 实验日志初始化失败")
		_trial_closed = true
		InputHub.input_frozen = true
		set_physics_process(false)
		_show_logging_failure()
		return

	# 正式关开场须知：弹窗展示期间输入冻结，玩家按任意键确认后才正式开始
	if not _def.intro_lines.is_empty():
		_show_intro_popup()
	else:
		ExperimentLog.log_event("intro_dismissed", {"note": "no_intro"})

## 离开关卡时清掉输入增益；session 文件由全局日志器跨 trial 保持打开。
func _exit_tree() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	HapticHub.end_level()
	AudioHub.stop_level_music(0.0)
	InputHub.reset_gains()
	if not _trial_closed:
		ExperimentLog.log_event("quit_mid_trial", {"note": "level_tree_exit"})
		_finish_trial("quit", "level_tree_exit")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _trial_closed:
		ExperimentLog.log_event("app_abort", {"outcome": "aborted", "note": "window_close"})
		_finish_trial("aborted", "window_close")

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
		_perturb.update(delta, true)
		_choice_tracker.update(delta)
		_update_tutorial_progress()
		_sample_trail(delta)
	# READY / RUNNING 都记采样，保证开局输入可复算
	if _state.phase == LevelState.Phase.READY or _state.phase == LevelState.Phase.RUNNING:
		ExperimentLog.set_task_context(
			_active_segment_id,
			_active_segment_type,
			_active_gate_id,
			_choice_tracker.get_active_choice_id(),
			_choice_tracker.get_current_branch(),
		)
		ExperimentLog.log_frame(
			delta,
			_phase_name(_state.phase),
			_ball,
		)

# ---------- 开场须知弹窗 ----------

## 弹出开场须知：冻结输入，展示文案，等待任意键确认
func _show_intro_popup() -> void:
	InputHub.input_frozen = true
	_intro_layer = CanvasLayer.new()
	_intro_layer.name = "IntroPopup"
	_intro_layer.layer = 30  # 压在 HUD（layer 20）之上
	add_child(_intro_layer)

	_intro_layer.add_child(MenuKit.make_dim_overlay(0.55))

	# 面板高度随文案行数自适应
	var line_h: float = 46.0
	var panel_size: Vector2 = Vector2(920.0, 250.0 + float(_def.intro_lines.size()) * line_h)
	var panel: NinePatchRect = MenuKit.make_panel(panel_size)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	_intro_layer.add_child(panel)
	UiSpring.attach(panel, 0.5, 0.35).pop_in(0.15)

	# 标题：面板内强调色 + 硬阴影（奶油底禁用奶油描边字）
	var title: Label = MenuKit.make_title_label(
		GameState.ui("准备开始！", "GET READY!"), 40, MenuKit.COL_ACCENT, true
	)
	title.position = Vector2(0.0, 52.0)
	title.size = Vector2(panel_size.x, 48.0)
	panel.add_child(title)

	# 正文：面板墨色，零描边
	for i: int in _def.intro_lines.size():
		var line: Label = MenuKit.make_panel_label(
			GameState.localize_content(_def.intro_lines[i]), 30
		)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.position = Vector2(0.0, 136.0 + float(i) * line_h)
		line.size = Vector2(panel_size.x, line_h)
		panel.add_child(line)

	# 底部行动提示：就绪绿，呼吸闪烁拉注意力但不抢标题
	var hint: HBoxContainer = MenuKit.make_device_hint_row(
		["ENTER"],
		["a"],
		GameState.ui("开始", "START"),
		40.0,
		InputHub.session_profile(),
	)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.position = Vector2(0.0, panel_size.y - 92.0)
	hint.size = Vector2(panel_size.x, 52.0)
	panel.add_child(hint)
	# 绑定到 hint 自身：弹窗销毁时 tween 一并终止
	var blink: Tween = hint.create_tween().set_loops()
	blink.tween_property(hint, "modulate:a", 0.25, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	blink.tween_property(hint, "modulate:a", 1.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## 开场弹窗任意键关闭；可暂停阶段响应 ESC / 手柄菜单键。
func _input(event: InputEvent) -> void:
	if _intro_layer != null:
		var confirmed: bool = false
		var key: InputEventKey = event as InputEventKey
		if key != null and key.pressed and not key.echo:
			confirmed = true
		var joy: InputEventJoypadButton = event as InputEventJoypadButton
		if joy != null and joy.pressed:
			confirmed = true
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse != null and mouse.pressed:
			confirmed = true
		if confirmed:
			get_viewport().set_input_as_handled()
			_dismiss_intro_popup()
		return

	if InputHub.is_pause_toggle_event(event) and _can_open_pause():
		get_viewport().set_input_as_handled()
		_open_pause_menu()

## 关闭弹窗：淡出后解冻输入，关卡等待第一次输入开始计时
func _dismiss_intro_popup() -> void:
	var layer: CanvasLayer = _intro_layer
	_intro_layer = null
	var fade: Tween = create_tween().set_parallel()
	for child: Node in layer.get_children():
		if child is CanvasItem:
			fade.tween_property(child, "modulate:a", 0.0, 0.16)
	fade.chain().tween_callback(layer.queue_free)
	InputHub.input_frozen = false
	ExperimentLog.log_event("intro_dismissed")

# ---------- 五关扩展：门 / 路段 / 扰动 / 岔路 ----------

## 按 LevelDef 装配门、不可见路段、扰动控制器与岔路追踪。
func _setup_challenge_components() -> void:
	_gates.clear()
	_segment_zones.clear()
	_active_segment_id = ""
	_active_segment_type = ""
	_active_gate_id = ""
	for gate_def: GateDef in _def.gates:
		var gate: BreakableGate = BreakableGate.new()
		_world.add_child(gate)
		gate.setup(gate_def, _ball)
		gate.gate_attempt.connect(_on_gate_attempt)
		gate.gate_failed.connect(_on_gate_failed)
		gate.gate_opened.connect(_on_gate_opened)
		_gates.append(gate)
	for seg_def: SegmentDef in _def.segments:
		var zone: RouteSegmentZone = RouteSegmentZone.new()
		_world.add_child(zone)
		zone.setup(seg_def, _ball)
		zone.segment_entered.connect(_on_segment_entered)
		zone.segment_exited.connect(_on_segment_exited)
		_segment_zones.append(zone)
	_perturb_spans.clear()
	_perturb_active = false
	_perturb_seconds = 0.0
	_perturb.perturb_changed.connect(_on_perturb_changed)
	_perturb.setup(_def, _ball, _segment_zones)
	_choice_tracker.setup(_def.choice_forks, _ball)

## 扰动开关：开始时新开一段轨迹，结束时收尾。
func _on_perturb_changed(active: bool, _slot: int, _gain: float) -> void:
	if active == _perturb_active:
		return
	_perturb_active = active
	if _hud != null:
		_hud.set_perturb_active(active, _state.elapsed)
	if active:
		_perturb_spans.append(PackedVector2Array([_ball.global_position]))
	elif not _perturb_spans.is_empty():
		# 只持续一两帧的扰动也留个点，结算图上画成标记
		_perturb_spans[_perturb_spans.size() - 1].append(_ball.global_position)

func _on_gate_attempt(gate_id: String, payload: Dictionary) -> void:
	_active_gate_id = gate_id
	var data: Dictionary = payload.duplicate()
	data["event_type_hint"] = "gate_attempt"
	ExperimentLog.log_event("gate_attempt", data)

func _on_gate_failed(gate_id: String, payload: Dictionary) -> void:
	_active_gate_id = gate_id
	ExperimentLog.log_event("gate_failed", payload)
	# 失败也要有撞墙级反馈：震屏 + 手柄震动，但不扣血
	var impact: float = maxf(float(payload.get("impact_strength", 120.0)), 120.0)
	_split_screen.shake(impact)
	AudioHub.play_gate_blocked()
	HapticHub.pulse_impact(false)

func _on_gate_opened(gate_id: String, payload: Dictionary) -> void:
	_active_gate_id = ""
	ExperimentLog.log_event("gate_opened", payload)
	if _def.is_practice:
		_tut_flags["gate_opened"] = true
	_play_gate_break_feedback()

## 撞开门：短顿帧 + 爆发震屏 + 大震动，对齐球被撞碎的冲击感。
func _play_gate_break_feedback() -> void:
	_split_screen.burst_shake()
	AudioHub.play_gate_break()
	HapticHub.pulse_impact(true)
	Engine.time_scale = 0.12
	await get_tree().create_timer(0.055, true, false, true).timeout
	Engine.time_scale = 1.0

func _on_segment_entered(segment_id: String, segment_type: String) -> void:
	_active_segment_id = segment_id
	_active_segment_type = segment_type
	ExperimentLog.log_event("segment_enter", {
		"segment_id": segment_id,
		"component_id": segment_id,
		"note": segment_type,
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
	})

func _on_segment_exited(segment_id: String, segment_type: String) -> void:
	if _active_segment_id == segment_id:
		_active_segment_id = ""
		_active_segment_type = ""
	ExperimentLog.log_event("segment_leave", {
		"segment_id": segment_id,
		"component_id": segment_id,
		"note": segment_type,
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
	})

## 定期采样球位置，供结算界面画核心轨迹
func _sample_trail(delta: float) -> void:
	if _perturb_active:
		_perturb_seconds += delta
	_trail_timer -= delta
	if _trail_timer > 0.0 or _trail.size() >= 1200:
		return
	_trail_timer = 0.12
	_trail.append(_ball.global_position)
	# 扰动区间与主轨迹同频采样，结算图上就是"时间线的一段"
	if _perturb_active and not _perturb_spans.is_empty():
		_perturb_spans[_perturb_spans.size() - 1].append(_ball.global_position)

## 死亡时把当前路线归档为失败轨迹，并清空以便记录下一命
func _archive_failed_trail() -> void:
	if _trail.size() >= 2:
		_failed_trails.append(_trail.duplicate())
	_trail = PackedVector2Array()
	_trail_timer = 0.0

## 出生点旗杆：永远压在地面贴花层（z=-1），不参与与球的前后遮挡计算。
func _spawn_spawn_marker() -> void:
	var marker: Node2D = Node2D.new()
	marker.name = "SpawnMarker"
	marker.position = _def.spawn_point
	marker.z_index = -1
	marker.z_as_relative = false
	# 旗影：贴在杆脚，略偏右下（与球/猴同一光源），淡到不抢通道
	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = _bake_spawn_shadow()
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.position = Vector2(2.0, 2.0)
	marker.add_child(shadow)
	var flag: Sprite2D = Sprite2D.new()
	flag.texture = _bake_spawn_flag()
	flag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flag.offset = Vector2(0.0, -12.0)  # 贴图高 24，脚底对齐出生点
	flag.scale = Vector2(1.5, 1.5)
	marker.add_child(flag)
	_world.add_child(marker)

## 烘焙 16x24 像素旗：木杆 + 三角旗面（蓝白格，开局感）
func _bake_spawn_flag() -> Texture2D:
	var ink: Color = Color("4a3325")
	var wood: Color = Color("926a4c")
	var blue: Color = Color("4a7ec0")
	var cream: Color = Color("f2e5bc")
	var img: Image = Image.create(16, 24, false, Image.FORMAT_RGBA8)
	# 木杆（x=3，从底到顶）
	for y: int in range(2, 24):
		img.set_pixel(3, y, wood)
		img.set_pixel(4, y, ink if y % 3 == 0 else wood)
	# 三角旗面：从杆向右展开，上宽下尖
	for y: int in range(2, 12):
		var tip: int = 14 - int(float(y - 2) * 0.7)
		for x: int in range(5, tip + 1):
			var checker: bool = ((x + y) % 2) == 0
			img.set_pixel(x, y, blue if checker else cream)
	# 旗尖描边加深一点轮廓
	img.set_pixel(3, 1, ink)
	return ImageTexture.create_from_image(img)

## 旗杆脚下的小阴影椭圆
func _bake_spawn_shadow() -> Texture2D:
	var img: Image = Image.create(12, 6, false, Image.FORMAT_RGBA8)
	for y: int in 6:
		for x: int in 12:
			var dx: float = (float(x) - 5.5) / 5.5
			var dy: float = (float(y) - 2.5) / 2.5
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.28))
	return ImageTexture.create_from_image(img)

func _spawn_goal() -> void:
	_goal = GoalArea.new()
	_goal.name = "Goal"
	_goal.position = _def.goal_point
	# 传送门永远在地面贴花层，不参与与球的前后遮挡
	_goal.z_index = -1
	_goal.z_as_relative = false
	_world.add_child(_goal)
	_goal.set_ball(_ball)
	_goal.reached.connect(_on_goal_reached)
	_goal.ball_entered.connect(func() -> void: ExperimentLog.log_event("goal_enter"))
	_goal.ball_left.connect(func() -> void: ExperimentLog.log_event("goal_leave"))

func _setup_health() -> void:
	_health = BallHealth.new()
	_health.name = "BallHealth"
	_ball.add_child(_health)
	_health.setup(_ball, _state)
	if not _ball.impacted.is_connected(_on_ball_collision):
		_ball.impacted.connect(_on_ball_collision)
	_health.died.connect(_on_ball_died)
	_health.damaged.connect(_on_ball_damaged)
	_health.impact_logged.connect(_on_impact_logged)

func _setup_hud() -> void:
	_hud = LevelHud.new()
	_hud.name = "LevelHud"
	add_child(_hud)
	# 第四关从开局就在计时器下亮「干扰」灯；不预告具体时间窗
	var show_jam_lamp: bool = (
		_def.challenge_type == "imbalance"
		and not _def.perturb_candidate_ids.is_empty()
	)
	_hud.setup(_state, _def.level_name, _def.time_limit, Vector2.ZERO, show_jam_lamp)

## 仅教学关 + 调试模式：左侧挂物理滑条，拖动即时生效。
func _setup_physics_debug() -> void:
	if _def == null or not _def.is_practice or not GameState.debug_mode:
		return
	_physics_debug = PhysicsDebugPanel.new()
	_physics_debug.name = "PhysicsDebugPanel"
	add_child(_physics_debug)
	_physics_debug.setup(_ball)

func _setup_pause_menu() -> void:
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.restart_requested.connect(_restart_from_pause)
	_pause_menu.level_select_requested.connect(_quit_to_level_select)

func _show_logging_failure() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	layer.add_child(MenuKit.make_dim_overlay(0.72))
	var panel_size := Vector2(760, 360)
	var panel: NinePatchRect = MenuKit.make_panel(panel_size)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 52
	box.offset_right = -52
	box.offset_top = 44
	box.offset_bottom = -44
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)
	box.add_child(MenuKit.make_title_label(
		GameState.ui("无法保存实验数据", "CANNOT SAVE EXPERIMENT DATA"),
		36, MenuKit.COL_DANGER, true
	))
	var message: Label = MenuKit.make_panel_label(
		GameState.ui(
			"试次尚未开始。请检查数据目录权限或磁盘空间后重试。",
			"The trial has not started. Check data-folder permissions or disk space, then retry."
		),
		23,
	)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	var button: Button = MenuKit.make_big_button(
		GameState.ui("返回标题", "BACK TO TITLE"), 24, Vector2(320, 76)
	)
	button.pressed.connect(func() -> void:
		InputHub.clear_slots()
		SceneDirector.go_to("res://scenes/title_screen.tscn")
	)
	var holder: HBoxContainer = HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(button)
	box.add_child(holder)
	button.grab_focus.call_deferred()

func _can_open_pause() -> bool:
	if _pause_menu == null or _pause_menu.is_open():
		return false
	if _state == null or _respawning:
		return false
	if _intro_layer != null:
		return false
	return (
		_state.phase == LevelState.Phase.READY
		or _state.phase == LevelState.Phase.RUNNING
	)

func _open_pause_menu() -> void:
	if not _can_open_pause():
		return
	InputHub.input_frozen = true
	_perturb.clear_active("pause")
	ExperimentLog.log_event("pause", {"phase": _phase_name(_state.phase)})
	_pause_menu.open_menu()
	get_tree().paused = true

func _resume_from_pause() -> void:
	if _pause_menu == null or not _pause_menu.is_open():
		return
	get_tree().paused = false
	_pause_menu.close_menu()
	ExperimentLog.log_event("resume", {"phase": _phase_name(_state.phase)})
	if (
		_intro_layer == null
		and not _respawning
		and _state != null
		and (
			_state.phase == LevelState.Phase.READY
			or _state.phase == LevelState.Phase.RUNNING
		)
	):
		InputHub.input_frozen = false

func _restart_from_pause() -> void:
	get_tree().paused = false
	if _pause_menu != null:
		_pause_menu.close_menu()
	InputHub.input_frozen = true
	ExperimentLog.log_event("restart_requested")
	_finish_trial("restarted")
	SceneDirector.go_to("res://scenes/level.tscn")

func _quit_to_level_select() -> void:
	get_tree().paused = false
	if _pause_menu != null:
		_pause_menu.close_menu()
	InputHub.input_frozen = true
	ExperimentLog.log_event("quit_mid_trial", {"note": "level_select_requested"})
	_finish_trial("quit", "level_select_requested")
	SceneDirector.go_to("res://scenes/level_select.tscn")

func _on_ball_damaged(_amount: float, _hp: float) -> void:
	_split_screen.shake(180.0)
	_hit_points.append(_ball.global_position)

func _on_ball_collision(strength: float, collision_category: String = PixelBall.COLLISION_ORDINARY) -> void:
	_perturb.notify_collision()
	AudioHub.play_ball_impact(strength, collision_category)
	ExperimentLog.log_event("collision", {
		"impact_strength": strength,
		"collision_category": collision_category,
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
	})

## 把实际伤害与致死碰撞写入实验事件日志。
func _on_impact_logged(strength: float, damage: float, _hp: float) -> void:
	var common: Dictionary = {
		"impact_strength": strength,
		"damage": damage,
		"remaining_hp": _hp,
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
	}
	ExperimentLog.log_event("damage", common)
	if _hp <= 0.0:
		ExperimentLog.log_event("death_collision", common)

func _on_ball_died() -> void:
	if _respawning or _state.phase == LevelState.Phase.FINISHED:
		return
	_respawning = true
	_state.enter_dead()
	ExperimentLog.log_event("respawn_start", {
		"phase": "dead",
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
	})
	InputHub.input_frozen = true
	await _respawn_sequence()

## 死亡 → 爆炸 → 相机回出生点 → 闪白重生（参考 Celeste / Mario）
func _respawn_sequence() -> void:
	var death_pos: Vector2 = _ball.global_position
	# 先归档本命轨迹，结算图里用虚线区分「失败尝试」
	_archive_failed_trail()

	# 1) 撞烂：爆炸 + 顿帧 + 重震屏，球立刻消失冻住
	BallBurst.play(_world, death_pos)
	AudioHub.play_ball_burst()
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
		ExperimentLog.log_event("time_penalty", {
			"time_penalty_s": _def.death_time_penalty,
		})

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
	_perturb.notify_respawn()
	ExperimentLog.begin_life()

func _on_goal_reached() -> void:
	if _state.phase != LevelState.Phase.RUNNING and _state.phase != LevelState.Phase.READY:
		return
	InputHub.input_frozen = true
	AudioHub.play_level_clear()
	# 星级：通关 1 星 + 满血 1 星 + 剩余时间 ≥ 限时 1/4 再 1 星；教程恒 3 星
	var full_hp: bool = _state.hp >= _state.max_hp - 0.01
	var time_ok: bool = _state.timed and _def.time_limit > 0.0 \
		and _state.time_left >= _def.time_limit * 0.25
	_state.finish(full_hp, time_ok, _def.is_practice)
	ExperimentLog.log_event("success", {
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
		"outcome": "success",
	})
	GameState.mark_cleared(_def.level_id)
	_finish_trial("success")
	# raw CSV 已落盘；派生分析在后台继续，不能阻塞传送演出。
	GameState.last_result = _build_result(true, _state.stars)
	await _teleport_sequence()
	SceneDirector.go_to("res://scenes/results_screen.tscn")

## 传送演出四拍：
## 1) 地面收束环锁定门心；2) 球短距离吸附；3) 细束从球后托起；
## 4) 暖白逐渐增强，上升到闪点后淡出。没有大白块，也不把门抬到角色前。
func _teleport_sequence() -> void:
	_ball.linear_velocity = Vector2.ZERO
	_ball.angular_velocity = 0.0
	_ball.freeze = true
	var col_shape: CollisionShape2D = _ball.get_node("CollisionShape2D") as CollisionShape2D
	col_shape.set_deferred("disabled", true)

	# 1) 独立 FX 前后分层；地面传送门只加速发亮，仍保持 z=-1。
	# 震动与传送演出同步起跑：弱 → 强，不阻塞动画时序。
	HapticHub.play_teleport_rumble(TeleportFx.DURATION)
	TeleportFx.play(_world, _goal.global_position)
	_goal.power_up(0.34)

	# 2) 球平稳吸附到中心，轻微压缩表示“被锁定”，不瞬移、不猛缩。
	var start_scale: Vector2 = _ball.scale
	var pull: Tween = create_tween().set_parallel()
	pull.tween_property(_ball, "global_position", _goal.global_position, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pull.tween_property(_ball, "scale", start_scale * 0.94, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pull.chain().tween_property(_ball, "scale", start_scale, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await pull.finished

	# 3) 影子先留在门心并淡掉，再开始升空；这样仍有明确的离地瞬间。
	var shadow: Sprite2D = _ball.get_node_or_null("Shadow") as Sprite2D
	if shadow != null:
		var fade_shadow: Tween = create_tween().set_parallel()
		fade_shadow.tween_property(shadow, "modulate:a", 0.0, 0.20)
		fade_shadow.tween_property(shadow, "scale", shadow.scale * 0.55, 0.20)
		await fade_shadow.finished
		shadow.visible = false

	# 4) 暖白只抬到 75%，保留球与猴子的颜色轮廓；上升后段才淡出。
	var flash_mat: ShaderMaterial = _apply_white_flash_to_riders()
	var flash: Tween = create_tween()
	flash.tween_method(
		func(v: float) -> void:
			flash_mat.set_shader_parameter("flash", v)
			_set_ball_white(v),
		0.0, 0.75, 0.62
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 升空时才进入前景层；传送门与地面环仍留在球下。
	_ball.z_index = 2
	_split_screen.shake(38.0)
	var rise: Tween = create_tween().set_parallel()
	rise.tween_property(_ball, "global_position:y", _ball.global_position.y - 148.0, 0.86) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	rise.tween_property(_ball, "scale", start_scale * 0.72, 0.86) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	rise.tween_property(_ball, "modulate:a", 0.0, 0.18).set_delay(0.68)
	await rise.finished
	_ball.visible = false
	await get_tree().create_timer(0.18).timeout

## 给球上所有角色贴图挂共享暖白材质；球体与所有影子必须排除。
func _apply_white_flash_to_riders() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = preload("res://shaders/white_flash.gdshader")
	var stack: Array[Node] = [_ball]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node.name == "BallSprite" or str(node.name).contains("Shadow"):
			continue  # 白底影子换掉 shadow shader 会变方块，必须保留原材质
		if node is Sprite2D or node is AnimatedSprite2D:
			(node as CanvasItem).material = mat
	return mat

## 球体白光（复用重生闪白 uniform）
func _set_ball_white(v: float) -> void:
	var sprite: Sprite2D = _ball.get_node_or_null("BallSprite") as Sprite2D
	if sprite != null and sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("spawn_flash", v)

func _on_failed() -> void:
	InputHub.input_frozen = true
	ExperimentLog.log_event("timeout_failure", {"outcome": "timeout"})
	_finish_trial("timeout")
	GameState.last_result = _build_result(false, 0)
	await get_tree().create_timer(0.5).timeout
	SceneDirector.go_to("res://scenes/results_screen.tscn")

## 结算数据：客观过程信息 + 团队级力度指标；不含单人贡献对比
func _build_result(success: bool, stars: int) -> Dictionary:
	var island_px: Vector2i = _builder.island_size_px()
	# 失败结算：当前未归档的路线也算失败尝试
	var failed: Array = _failed_trails.duplicate()
	var win_trail: PackedVector2Array = PackedVector2Array()
	if success:
		win_trail = _trail
	elif _trail.size() >= 2:
		failed.append(_trail.duplicate())
	var result: Dictionary = {
		"level_id": _def.level_id,
		"level_name": _def.level_name,
		"elapsed": _state.elapsed,
		"time_left": _state.time_left if success else 0.0,
		"timed": _state.timed,
		"hp": _state.hp,
		"max_hp": _state.max_hp,
		"stars": stars,
		"success": success,
		"practice": _def.is_practice,
		"trail": win_trail,
		"failed_trails": failed,
		"hits": _hit_points,
		"island": Vector2(island_px),
		"spawn": _def.spawn_point,
		"goal": _def.goal_point,
		"perturb_spans": _perturb_spans.duplicate(),
		"perturb_count": _perturb_spans.size(),
		"perturb_seconds": _perturb_seconds,
	}
	var summary: Dictionary = ExperimentLog.summary_dict()
	for key: Variant in summary.keys():
		result[key] = summary[key]
	return result

func _on_phase_changed(phase: LevelState.Phase) -> void:
	if phase == LevelState.Phase.RUNNING and not _respawning:
		AudioHub.start_level_music()
		ExperimentLog.log_event("run_start", {"phase": "running"})
	elif phase == LevelState.Phase.FINISHED or phase == LevelState.Phase.FAILED:
		AudioHub.stop_level_music()

func _finish_trial(outcome: String, note: String = "") -> void:
	if _trial_closed:
		return
	_perturb.clear_active("trial_end")
	ExperimentLog.end_trial(outcome, note)
	_trial_closed = true

func _phase_name(phase: LevelState.Phase) -> String:
	match phase:
		LevelState.Phase.READY:
			return "ready"
		LevelState.Phase.RUNNING:
			return "running"
		LevelState.Phase.DEAD:
			return "dead"
		LevelState.Phase.FINISHED:
			return "finished"
		LevelState.Phase.FAILED:
			return "failed"
	return "unknown"

## 根据玩家行为推进练习关教程（含连续力度教学步骤）
func _update_tutorial_progress() -> void:
	if _def.tutorial_steps.is_empty():
		return
	var step: int = _state.tutorial_step
	var s1: ForceMapper.Sample = InputHub.get_force_sample(0)
	var s2: ForceMapper.Sample = InputHub.get_force_sample(1)
	var v1: Vector2 = s1.move
	var v2: Vector2 = s2.move
	var i1: float = s1.m2 * s1.gain
	var i2: float = s2.m2 * s2.gain
	# 0: 满推起步
	if step == 0 and (i1 >= 0.85 or i2 >= 0.85) and _ball.linear_velocity.length() > 35.0:
		_state.advance_tutorial()
	# 1: 半推转向（中段力度）
	elif step == 1 and (
		(i1 > 0.2 and i1 < 0.75) or (i2 > 0.2 and i2 < 0.75)
	) and _ball.linear_velocity.length() > 15.0:
		_state.advance_tutorial()
	# 2: 回中制动（有输入后出现松手）
	elif step == 2:
		if i1 > 0.35 or i2 > 0.35:
			_tut_flags["pushed"] = true
		if bool(_tut_flags.get("pushed", false)) and i1 < 0.08 and i2 < 0.08:
			_state.advance_tutorial()
	# 3: 同向推
	elif step == 3 and v1 != Vector2.ZERO and v2 != Vector2.ZERO:
		if v1.dot(v2) > 0.5:
			_tut_flags["same"] = true
		if bool(_tut_flags.get("same", false)) and _ball.linear_velocity.length() > 40.0:
			_state.advance_tutorial()
	# 4: 反向旋转
	elif step == 4 and v1 != Vector2.ZERO and v2 != Vector2.ZERO:
		if v1.dot(v2) < -0.3 and absf(_ball.angular_velocity) > 1.0:
			_state.advance_tutorial()
	# 5: 撞击掉血
	elif step == 5 and _state.hp < _state.max_hp - 0.5:
		_state.advance_tutorial()
	# 6: 加速撞开教学门（若玩家提前撞开，也能在到达此步骤后继续）
	elif step == 6 and bool(_tut_flags.get("gate_opened", false)):
		_state.advance_tutorial()
	# 7: 到达终点附近
	elif step == 7:
		if _ball.global_position.distance_to(_def.goal_point) < 120.0:
			_state.advance_tutorial()
