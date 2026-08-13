extends SceneTree
## 作者关可达性断言：对球心做网格 BFS（R=44）。
## 覆盖第 2/3 共用 gauntlet，以及新加的第 4、5 关。
## 用法：godot --headless --path . --script res://tools/gauntlet_reachability_assert.gd

const BALL_RADIUS: float = 44.0
const CELL: float = 6.0
const WALL_MARGIN: float = 8.0 + BALL_RADIUS

const LEVEL_CASES: Array[Dictionary] = [
	{
		"path": "res://levels/level_2.tres",
		"waypoints": [
			Vector2(150.0, 425.0),
			Vector2(250.0, 412.0),
			Vector2(320.0, 300.0),
			Vector2(500.0, 110.0),
			Vector2(580.0, 200.0),
			Vector2(720.0, 130.0),
			Vector2(800.0, 280.0),
			Vector2(840.0, 250.0),
			Vector2(980.0, 360.0),
		],
	},
	{
		"path": "res://levels/level_4.tres",
		"waypoints": [
			Vector2(500.0, 540.0),
			Vector2(1000.0, 500.0),
			Vector2(850.0, 340.0),
			Vector2(180.0, 340.0),
			Vector2(120.0, 130.0),
			Vector2(500.0, 130.0),
		],
	},
	{
		"path": "res://levels/level_5.tres",
		"waypoints": [
			Vector2(420.0, 610.0),
			Vector2(850.0, 520.0),
			Vector2(850.0, 220.0),
			Vector2(500.0, 90.0),
			Vector2(100.0, 180.0),
			Vector2(100.0, 360.0),
			Vector2(250.0, 350.0),
			Vector2(430.0, 350.0),
		],
	},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var input_hub: Node = root.get_node("InputHub")
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)
	input_hub.call("join_slot", 1, 2)
	input_hub.set("input_frozen", false)
	game_state.set("experiment_condition", "baseline")

	for case_data: Dictionary in LEVEL_CASES:
		var path: String = str(case_data["path"])
		var ok: bool = await _assert_level(game_state, path, case_data["waypoints"] as Array)
		if not ok:
			quit(1)
			return

	print("gauntlet_reachability OK for %d levels" % LEVEL_CASES.size())
	quit(0)

func _assert_level(game_state: Node, path: String, waypoints: Array) -> bool:
	game_state.set("current_level", load(path))
	var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()

	var def: Resource = game_state.get("current_level")
	var spawn: Vector2 = def.get("spawn_point")
	var goal: Vector2 = def.get("goal_point")
	var island: Vector2i = def.get("island_size")
	var world_w: float = float(island.x * 16)
	var world_h: float = float(island.y * 16)
	var world: Node2D = level.find_child("World", true, false) as Node2D
	var obstacles: Array[Dictionary] = _collect_circles(world)
	print("reachability %s obstacles=%d spawn=%s goal=%s" % [
		path.get_file(), obstacles.size(), spawn, goal,
	])

	if not _point_free(spawn, obstacles, world_w, world_h):
		push_error("%s spawn blocked" % path)
		level.queue_free()
		return false
	if not _point_free(goal, obstacles, world_w, world_h):
		push_error("%s goal blocked" % path)
		level.queue_free()
		return false
	if not _bfs(spawn, goal, obstacles, world_w, world_h):
		push_error("%s NO PATH spawn→goal" % path)
		level.queue_free()
		return false

	for wp_variant: Variant in waypoints:
		var wp: Vector2 = wp_variant as Vector2
		var cell: Vector2i = Vector2i(int(wp.x / CELL), int(wp.y / CELL))
		var free_cell: Vector2i = _nearest_free_cell(
			cell, obstacles, world_w, world_h,
			int(WALL_MARGIN / CELL), int(WALL_MARGIN / CELL),
			int((world_w - WALL_MARGIN) / CELL), int((world_h - WALL_MARGIN) / CELL),
		)
		if free_cell.x < 0:
			push_error("%s waypoint sealed: %s" % [path, wp])
			level.queue_free()
			return false
		var free_wp: Vector2 = Vector2(float(free_cell.x) * CELL, float(free_cell.y) * CELL)
		if not _bfs(spawn, free_wp, obstacles, world_w, world_h):
			push_error("%s waypoint unreachable: %s (~%s)" % [path, wp, free_wp])
			level.queue_free()
			return false

	level.queue_free()
	await process_frame
	return true

func _collect_circles(world: Node2D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_walk(world, out)
	return out

func _walk(node: Node, out: Array[Dictionary]) -> void:
	if node is RigidBody2D or node.name == "Ball":
		return
	if node is CollisionShape2D:
		var cs: CollisionShape2D = node as CollisionShape2D
		if cs.shape is CircleShape2D:
			var circle: CircleShape2D = cs.shape as CircleShape2D
			out.append({
				"kind": "circle",
				"c": cs.global_position,
				"r": circle.radius,
			})
		elif cs.shape is RectangleShape2D:
			var rect: RectangleShape2D = cs.shape as RectangleShape2D
			var half: Vector2 = rect.size * 0.5
			out.append({
				"kind": "rect",
				"c": cs.global_position,
				"half": half,
			})
	for child: Node in node.get_children():
		_walk(child, out)

func _point_free(
	p: Vector2,
	obstacles: Array[Dictionary],
	world_w: float,
	world_h: float,
) -> bool:
	if p.x < WALL_MARGIN or p.x > world_w - WALL_MARGIN:
		return false
	if p.y < WALL_MARGIN or p.y > world_h - WALL_MARGIN:
		return false
	for obs: Dictionary in obstacles:
		if obs["kind"] == "circle":
			var need: float = BALL_RADIUS + float(obs["r"])
			if p.distance_to(obs["c"] as Vector2) < need - 0.5:
				return false
		else:
			var c: Vector2 = obs["c"] as Vector2
			var half: Vector2 = obs["half"] as Vector2
			var dx: float = maxf(absf(p.x - c.x) - half.x, 0.0)
			var dy: float = maxf(absf(p.y - c.y) - half.y, 0.0)
			if dx * dx + dy * dy < BALL_RADIUS * BALL_RADIUS - 0.25:
				return false
	return true

func _bfs(
	start: Vector2,
	goal: Vector2,
	obstacles: Array[Dictionary],
	world_w: float,
	world_h: float,
) -> bool:
	var x0: int = int(WALL_MARGIN / CELL)
	var y0: int = int(WALL_MARGIN / CELL)
	var x1: int = int((world_w - WALL_MARGIN) / CELL)
	var y1: int = int((world_h - WALL_MARGIN) / CELL)
	var start_i: Vector2i = Vector2i(int(start.x / CELL), int(start.y / CELL))
	var goal_i: Vector2i = Vector2i(int(goal.x / CELL), int(goal.y / CELL))
	start_i = _nearest_free_cell(start_i, obstacles, world_w, world_h, x0, y0, x1, y1)
	goal_i = _nearest_free_cell(goal_i, obstacles, world_w, world_h, x0, y0, x1, y1)
	if start_i.x < 0 or goal_i.x < 0:
		return false

	var visited: Dictionary = {}
	var q: Array[Vector2i] = [start_i]
	visited[start_i] = true
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var guard: int = 0
	while not q.is_empty() and guard < 200000:
		guard += 1
		var cur: Vector2i = q.pop_front()
		if cur.distance_squared_to(goal_i) <= 2:
			return true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < x0 or nxt.x > x1 or nxt.y < y0 or nxt.y > y1:
				continue
			if visited.has(nxt):
				continue
			var p: Vector2 = Vector2(float(nxt.x) * CELL, float(nxt.y) * CELL)
			if not _point_free(p, obstacles, world_w, world_h):
				continue
			visited[nxt] = true
			q.append(nxt)
	return false

func _nearest_free_cell(
	cell: Vector2i,
	obstacles: Array[Dictionary],
	world_w: float,
	world_h: float,
	x0: int, y0: int, x1: int, y1: int,
) -> Vector2i:
	for radius: int in range(0, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var c: Vector2i = cell + Vector2i(dx, dy)
				if c.x < x0 or c.x > x1 or c.y < y0 or c.y > y1:
					continue
				var p: Vector2 = Vector2(float(c.x) * CELL, float(c.y) * CELL)
				if _point_free(p, obstacles, world_w, world_h):
					return c
	return Vector2i(-1, -1)
