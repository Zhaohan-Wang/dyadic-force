extends SceneTree
## 关卡布局冒烟：五关主题字段、时限、扰动组件与无紫条 HUD。
## 用法：godot --headless --path . --script res://tools/level_layout_smoke.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var input_hub: Node = root.get_node("InputHub")
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)
	input_hub.call("join_slot", 1, 2)
	input_hub.set("input_frozen", false)
	input_hub.call("reset_gains")
	game_state.set("experiment_condition", "perturbation")
	game_state.set("current_level", load("res://levels/level_4.tres"))

	var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()
	input_hub.set("input_frozen", false)

	var def1: Resource = load("res://levels/level_1.tres")
	var def2: Resource = load("res://levels/level_2.tres")
	var def3: Resource = load("res://levels/level_3.tres")
	var def4: Resource = load("res://levels/level_4.tres")
	var def5: Resource = load("res://levels/level_5.tres")

	assert(str(def1.get("challenge_type")) == "joint_start", "L1 challenge")
	assert(str(def2.get("challenge_type")) == "joint_brake", "L2 challenge")
	assert(str(def3.get("challenge_type")) == "turn_coord", "L3 challenge")
	assert(str(def4.get("challenge_type")) == "imbalance", "L4 challenge")
	assert(str(def5.get("challenge_type")) == "route_choice", "L5 challenge")
	assert((def1.get("gates") as Array).size() == 3, "L1 must have 3 gates")
	# 第 3/5 关复用第 1 关的门作为节奏点：门只在共享路段上，不落在岔路分支里
	assert((def3.get("gates") as Array).size() == 2, "L3 must reuse 2 gates")
	assert((def4.get("gates") as Array).is_empty(), "L4 must stay gate-free")
	assert((def5.get("gates") as Array).size() == 1, "L5 must reuse 1 gate")
	assert((def4.get("perturb_candidate_ids") as PackedStringArray).size() >= 3, "L4 candidates")
	assert(bool(def4.get("perturb_continuous")), "L4 must perturb continuously")
	assert(float(def4.get("perturb_duration_min_s")) >= 8.0, "L4 bursts must last longer")
	assert(float(def4.get("perturb_min_gap_s")) <= 1.5, "L4 gaps must stay short")
	assert(int(def4.get("perturb_target_count")) >= 12, "L4 must cover the whole clock")
	assert((def5.get("choice_forks") as Array).size() == 2, "L5 two forks")
	assert(def1.get("dampen_window") == Vector2.ZERO, "legacy dampen unused")
	assert(def3.get("dampen_window") == Vector2.ZERO, "L3 no time-window dampen")
	assert(is_equal_approx(float(def1.get("time_limit")), 120.0), "official time 120")
	assert(is_equal_approx(float(def4.get("time_limit")), 120.0), "L4 time 120")

	var hud: Node = level.find_child("LevelHud", true, false)
	assert(hud != null, "LevelHud missing")
	# 紫条窗口必须为零：不向玩家显示扰动规律
	var mark: Variant = hud.get("_dampen_mark")
	if mark != null and mark is CanvasItem:
		assert(not (mark as CanvasItem).visible, "purple jam mark must stay hidden")

	# 第四关从开局就亮「干扰」灯，不等人走进候选段
	assert(bool(hud.get("_show_jam_lamp")), "L4 must light the jam lamp from the start")
	var badge: CanvasItem = hud.get("_skew_badge") as CanvasItem
	assert(badge != null and badge.visible, "jam lamp must be visible at L4 start")
	assert(hud.get("_skew_band") == null, "skew band must not exist before any perturb")
	hud.call("set_perturb_active", true, 20.0)
	assert(badge.visible, "jam lamp stays on while perturbing")
	var band: ColorRect = hud.get("_skew_band") as ColorRect
	assert(band != null, "skew band missing on perturb start")
	var start_x: float = band.position.x
	# 条从右往左缩短，已用时越多标记左边界越往左，宽度随之增长
	hud.call("_on_time", 96.0, 24.0, true)
	assert(band.position.x < start_x, "skew band should grow leftwards")
	assert(band.size.x > 4.0, "skew band width should grow: %.1f" % band.size.x)
	hud.call("set_perturb_active", false, 24.0)
	assert(badge.visible, "jam lamp stays on after perturb ends")
	assert(hud.get("_skew_band") == null, "current band handle released")
	assert(band.get_parent() != null, "finished band must stay on the bar as history")

	var gates: Array = level.get("_gates") as Array
	assert(gates.is_empty(), "L4 should not spawn gates")

	var zones: Array = level.get("_segment_zones") as Array
	assert(zones.size() >= 3, "L4 should spawn perturb segment zones")

	print("level_layout_smoke OK")
	quit(0)
