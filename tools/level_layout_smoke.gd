extends SceneTree
## 关卡布局冒烟：第 2/3 关共享出生/终点/时限；扰动条件下 HUD 干扰带与 50% 增益切换可用。
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
	game_state.set("current_level", load("res://levels/level_3.tres"))

	var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()
	input_hub.set("input_frozen", false)

	var hud: Node = level.find_child("LevelHud", true, false)
	if hud == null:
		push_error("level_layout_smoke: LevelHud missing")
		quit(1)
		return

	var def3: Resource = load("res://levels/level_3.tres")
	var def2: Resource = load("res://levels/level_2.tres")
	var def4: Resource = load("res://levels/level_4.tres")
	var def5: Resource = load("res://levels/level_5.tres")
	assert(def2.get("spawn_point") == def3.get("spawn_point"), "L2/L3 share spawn")
	assert(def2.get("goal_point") == def3.get("goal_point"), "L2/L3 share goal")
	assert(is_equal_approx(float(def2.get("time_limit")), float(def3.get("time_limit"))), "L2/L3 share time")
	assert(
		def4.get("route_centerline") != def2.get("route_centerline"),
		"L4 must not reuse the L2/L3 route",
	)
	assert(
		def5.get("route_centerline") != def2.get("route_centerline")
		and def5.get("route_centerline") != def4.get("route_centerline"),
		"L5 must use its own route",
	)
	assert(
		is_equal_approx(float(def4.get("time_limit")), float(def5.get("time_limit"))),
		"L4/L5 should share the official time limit",
	)
	assert(def2.get("dampen_window") == Vector2.ZERO, "L2 has no jam window")
	assert(def3.get("dampen_window") == Vector2(8, 50), "L3 jam window 8..50")
	assert(float(def3.get("spawn_point").y) > 380.0, "spawn in bottom corridor")
	assert(float(def3.get("goal_point").y) < 250.0, "goal near chimney top")

	var src: String = FileAccess.get_file_as_string("res://scripts/level.gd")
	assert(src.contains("DAMPEN_FACTOR: float = 0.50"), "DAMPEN_FACTOR must be 0.50")

	assert(hud.get("_dampen_mark") != null, "purple jam mark must exist")
	assert(hud.get("_dampen_label") != null, "JAM label must exist")
	assert(hud.get("_jam_badge") != null, "jam badge node must exist")

	var state: Object = level.get("_state")
	state.set("elapsed", 12.0)
	level.set("_dampen_slot", -1)
	level.set("_dampen_left", 0.0)
	level.call("_update_input_dampen", 0.1)

	var gains: Array = input_hub.get("slot_gains")
	var min_gain: float = minf(float(gains[0]), float(gains[1]))
	var max_gain: float = maxf(float(gains[0]), float(gains[1]))
	assert(min_gain <= 0.55 and max_gain >= 0.99, "expected ~50%%/100%% gains, got %s" % [gains])
	assert(bool(hud.get("_jam_badge").visible), "jam badge should show while dampened")

	print("level_layout_smoke OK gains=%s" % [gains])
	quit(0)
