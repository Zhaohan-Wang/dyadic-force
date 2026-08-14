class_name BreakableGate
extends StaticBody2D
## 可撞门：Sprout Lands 栅栏门（两端立柱 + 上下两扇木栅）。
## 成功：两扇栅栏向外倒下 + 木屑爆发，立柱留在原处；失败：按接近阈值只顶开一点再弹回。
## 任何与门的碰撞都不扣血（震屏 / 手柄震动由关卡层触发）。

## 关卡里已经在用的栅栏图集，门柱直接复用，保证和灌木墙同一套像素
const TEX_FENCE: Texture2D = preload("res://assets/tiles/fences.png")
## 与 fences.png 采样一致的木色
const COL_OUTLINE: Color = Color("6b4a2a")
const COL_PLANK: Color = Color("c49a6c")
const COL_GAP: Color = Color("aa7959")
const COL_RAIL: Color = Color("e8cfa6")
const COL_RAIL_SHADE: Color = Color("b78a62")
const COL_POST: Color = Color("e8cfa6")
const COL_HINGE: Color = Color("7a7268")
## 门叶厚度（像素），对齐碰撞厚度
const LEAF_THICK: int = 18

enum GateState {
	CLOSED,
	OPENING,
	OPENED,
}

signal gate_attempt(gate_id: String, payload: Dictionary)
signal gate_failed(gate_id: String, payload: Dictionary)
signal gate_opened(gate_id: String, payload: Dictionary)

## 配置资源
var def: GateDef
## 球引用（用于速度与接触检测）
var _ball: PixelBall = null
## 当前状态
var _state: GateState = GateState.CLOSED
## 是否处于同一次接触中（防重复记尝试）
var _in_contact: bool = false
## 失败刹停冷却，避免同一接触反复改速度
var _stop_cooldown: float = 0.0
## 失败后继续吸收冲向门的速度，防止球材质弹性把球弹飞
var _absorb_inward_s: float = 0.0
## 贴上门之前冲向门的速度（物理吸收会把当前速度清掉，判定必须用这个）
var _approach_speed: float = 0.0
## 贴上门之前球的来向（沿门轴，指向穿过方向）。重叠瞬间球可能已越过中面，来向必须提前锁存。
var _approach_dir: Vector2 = Vector2.ZERO
## 本次撞击最终采用的穿门方向：动画镜像、速度吸收、成功减速都以它为基准
var _pass_dir: Vector2 = Vector2.RIGHT
## 已排队等本帧结束再判定（避免和球的 notify_impact 抢两次）
var _judge_queued: bool = false
## 碰撞形状
var _shape: CollisionShape2D = null
## 整座门的美术根（影子 / 石柱 / 门叶）
var _art_root: Node2D = null
## 两扇门叶的父节点（失败时整体让位）
var _visual_holder: Node2D = null
## 上下两扇栅栏（撞开时分别向外倒下）
var _panel_left: Node2D = null
var _panel_right: Node2D = null
## 门叶静息位置（失败动画结束后要弹回这里）
var _panel_left_rest: Vector2 = Vector2.ZERO
var _panel_right_rest: Vector2 = Vector2.ZERO
## 铺在地上的门影，撞开后淡出
var _ground_shadow: Sprite2D = null
## 失败“几乎推开”动画
var _fail_tween: Tween = null
## 力采样缓冲：最近 window 内的 A/B 力（用于判定）
var _force_history: Array[Dictionary] = []
## 历史最大保留秒数
const HISTORY_KEEP_S: float = 0.50
## 失败后继续吸收冲向门速度的时长（秒）
const FAIL_ABSORB_S: float = 0.18
## 失败离开门的微弱回弹上限（像素/秒）；远小于球速，几乎贴门停下
const FAIL_REBOUND_MAX: float = 12.0
## 失败时切向速度保留比例，避免贴门滑飞
const FAIL_TANGENT_KEEP: float = 0.40
## 失败时角速度保留比例
const FAIL_SPIN_KEEP: float = 0.45
## 撞开后保留的法向速度比例：成功本身已经给反馈，动量吃掉九成
const SUCCESS_SPEED_KEEP: float = 0.10
## 撞开后最低穿门速度，只保证不会卡在已关掉的碰撞体里
const SUCCESS_MIN_THROUGH: float = 8.0
## 没撞开时门板最大转角：只顶开一小缝
const FAIL_OPEN_ANGLE_MAX_DEG: float = 15.0
## 轻撞时的最小转角
const FAIL_OPEN_ANGLE_MIN_DEG: float = 5.0
## 没撞开时沿穿过方向的最大让位
const FAIL_KICK_MAX: float = 8.0
## 没撞开时两扇在开口方向裂开的最大间距
const FAIL_SPREAD_MAX: float = 6.0
## 接触盒比实体多出来的法向余量：必须在速度被吸收前就判定
const CONTACT_SLACK_PX: float = 16.0
## 立柱相对 16px 栅栏格的放大倍数
const POST_SCALE: float = 3.0

func setup(gate_def: GateDef, ball: PixelBall) -> void:
	def = gate_def
	_ball = ball
	name = "BreakableGate_%s" % def.gate_id
	add_to_group("breakable_gate")
	position = def.position
	# 吸收球自身弹性：门接触合成弹性为 0，不会被物理引擎弹飞
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.bounce = 1.0
	mat.absorbent = true
	mat.friction = 0.70
	physics_material_override = mat
	_pass_dir = _gate_axis()
	_build_visual_and_collision()

func _build_visual_and_collision() -> void:
	var normal: Vector2 = _gate_axis()
	var along_normal: float = def.thickness
	var along_tangent: float = def.opening_width

	_shape = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	if absf(normal.x) >= absf(normal.y):
		box.size = Vector2(along_normal, along_tangent)
	else:
		box.size = Vector2(along_tangent, along_normal)
	_shape.shape = box
	add_child(_shape)

	_art_root = Node2D.new()
	_art_root.name = "ArtRoot"
	add_child(_art_root)

	# 地面长影：左上光，影子偏右下，把整排栅栏钉在草地上
	_ground_shadow = _make_nn_sprite(_bake_oval_shadow(28, int(along_tangent) + 16))
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.z_index = -2
	_ground_shadow.position = Vector2(8.0, 7.0)
	_art_root.add_child(_ground_shadow)

	# 开口两端立柱：复用关卡栅栏柱，撞开后还留着
	var half: float = along_tangent * 0.5
	_art_root.add_child(_make_fence_post(Vector2(0.0, -half), false))
	_art_root.add_child(_make_fence_post(Vector2(0.0, half), true))

	_visual_holder = Node2D.new()
	_visual_holder.name = "VisualHolder"
	_visual_holder.z_index = 6
	_art_root.add_child(_visual_holder)

	# 上下两扇，铰链分别靠北柱 / 南柱，中间对缝
	var leaf_h: int = maxi(int(along_tangent * 0.5) - 10, 48)
	_panel_left = _make_leaf(leaf_h, true)
	_panel_right = _make_leaf(leaf_h, false)
	_visual_holder.add_child(_panel_left)
	_visual_holder.add_child(_panel_right)
	_panel_left_rest = _panel_left.position
	_panel_right_rest = _panel_right.position

## 栅栏立柱：放大后脚底仍钉在开口端点。
func _make_fence_post(local_pos: Vector2, in_front: bool) -> Node2D:
	var holder: Node2D = Node2D.new()
	holder.name = "PostFront" if in_front else "PostBack"
	holder.position = local_pos
	holder.z_index = 8 if in_front else 3
	var blob: Sprite2D = _make_nn_sprite(_bake_oval_shadow(28, 14))
	blob.position = Vector2(6.0, 4.0)
	blob.z_index = -1
	holder.add_child(blob)
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = TEX_FENCE
	spr.region_enabled = true
	spr.region_rect = Rect2(0.0, 0.0, 16.0, 16.0)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = false
	# 贴图底边中点对齐节点原点，放大绕柱脚
	spr.offset = Vector2(-8.0, -16.0)
	spr.scale = Vector2(POST_SCALE, POST_SCALE)
	holder.add_child(spr)
	return holder

## 一扇栅栏门叶。is_upper：北侧扇，铰链在上沿，门板往开口中心长。
func _make_leaf(leaf_h: int, is_upper: bool) -> Node2D:
	var holder: Node2D = Node2D.new()
	holder.name = "PanelUpper" if is_upper else "PanelLower"
	var hinge_y: float = -float(leaf_h) if is_upper else float(leaf_h)
	holder.position = Vector2(0.0, hinge_y)
	var tex: Texture2D = _bake_fence_leaf(LEAF_THICK, leaf_h)
	var toward: float = float(leaf_h) * 0.5 * (1.0 if is_upper else -1.0)
	var drop: Sprite2D = _make_nn_sprite(tex)
	drop.modulate = Color(0.08, 0.05, 0.03, 0.35)
	drop.position = Vector2(4.0, toward + 3.0)
	drop.z_index = -1
	holder.add_child(drop)
	var spr: Sprite2D = _make_nn_sprite(tex)
	spr.position = Vector2(0.0, toward)
	holder.add_child(spr)
	return holder

## 用栅栏同色画出一扇实心木栅：竖板 + 横档 + 铰链，不拉伸任何小图。
func _bake_fence_leaf(width: int, height: int) -> Texture2D:
	var img: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		for x: int in width:
			var color: Color = COL_PLANK
			if x == 0 or y == 0 or x == width - 1 or y == height - 1:
				color = COL_OUTLINE
			elif x <= 3:
				color = COL_POST if x == 1 else COL_RAIL_SHADE
			elif (x - 4) % 5 == 4:
				color = COL_GAP
			img.set_pixel(x, y, color)
	# 横档：和岛边栅栏一样两根一组
	var rail_ys: Array[int] = [6, 10]
	var y_cursor: int = 22
	while y_cursor < height - 8:
		rail_ys.append(y_cursor)
		rail_ys.append(y_cursor + 4)
		y_cursor += 16
	for rail_y: int in rail_ys:
		if rail_y < 1 or rail_y >= height - 1:
			continue
		for x: int in range(1, width - 1):
			img.set_pixel(x, rail_y, COL_RAIL if rail_y % 2 == 0 else COL_RAIL_SHADE)
	# 铰链钉在立柱一侧
	var mid_y: int = int(float(height) * 0.5)
	for hinge_y: int in [12, mid_y, height - 14]:
		if hinge_y < 2 or hinge_y >= height - 3:
			continue
		for x: int in range(1, 5):
			img.set_pixel(x, hinge_y, COL_HINGE)
			img.set_pixel(x, hinge_y + 1, COL_OUTLINE)
	return ImageTexture.create_from_image(img)

## 软边椭圆影，铺在脚下。
func _bake_oval_shadow(w: int, h: int) -> Texture2D:
	var img: Image = Image.create(maxi(w, 2), maxi(h, 2), false, Image.FORMAT_RGBA8)
	var cx: float = float(w - 1) * 0.5
	var cy: float = float(h - 1) * 0.5
	var rx: float = maxf(float(w) * 0.5, 1.0)
	var ry: float = maxf(float(h) * 0.5, 1.0)
	for y: int in h:
		for x: int in w:
			var nx: float = (float(x) - cx) / rx
			var ny: float = (float(y) - cy) / ry
			var dist: float = nx * nx + ny * ny
			if dist > 1.0:
				continue
			var alpha: float = 0.42 * clampf(1.0 - dist, 0.12, 1.0)
			img.set_pixel(x, y, Color(0.10, 0.07, 0.04, alpha))
	return ImageTexture.create_from_image(img)

## 最近邻像素精灵，避免放大发糊
func _make_nn_sprite(tex: Texture2D) -> Sprite2D:
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return spr

## 门轴：def.normal 只描述"门横跨哪条轴"，正负号不限制撞门方向。
func _gate_axis() -> Vector2:
	if def == null:
		return Vector2.RIGHT
	var axis: Vector2 = def.normal.normalized()
	if axis == Vector2.ZERO:
		return Vector2.RIGHT
	return axis

## 解算穿门方向：从球所在一侧指向门，"从左往右撞"和"从右往左撞"都成立。
func _resolve_pass_dir() -> Vector2:
	var axis: Vector2 = _gate_axis()
	if _ball == null:
		return axis
	var along: float = (global_position - _ball.global_position).dot(axis)
	if absf(along) < 1.0:
		# 球几乎压在门中面上，位置分不出来向，退回用速度方向
		along = _ball.linear_velocity.dot(axis)
	return axis if along >= 0.0 else -axis

## 判定用的穿门方向：优先用贴门前锁存的来向，其次现算。
func _judge_dir() -> Vector2:
	if _approach_dir != Vector2.ZERO:
		return _approach_dir
	return _resolve_pass_dir()

func _physics_process(delta: float) -> void:
	if _stop_cooldown > 0.0:
		_stop_cooldown = maxf(0.0, _stop_cooldown - delta)
	if _absorb_inward_s > 0.0:
		_absorb_inward_s = maxf(0.0, _absorb_inward_s - delta)
		_absorb_inward_velocity()
	if _state != GateState.CLOSED or _ball == null or def == null:
		return
	_sample_forces()
	_update_contact_and_judge()

## 采样双方当前力，供碰撞窗口回放
func _sample_forces() -> void:
	var now_us: int = Time.get_ticks_usec()
	var slot_a: int = GameState.participant_a_slot
	var sample_a: ForceMapper.Sample = InputHub.get_force_sample(slot_a)
	var sample_b: ForceMapper.Sample = InputHub.get_force_sample(1 - slot_a)
	_force_history.append({
		"t_us": now_us,
		"a": sample_a.force,
		"b": sample_b.force,
	})
	var cutoff: int = now_us - int(HISTORY_KEEP_S * 1_000_000.0)
	while not _force_history.is_empty() and int(_force_history[0]["t_us"]) < cutoff:
		_force_history.remove_at(0)

func _update_contact_and_judge() -> void:
	# 用"从球指向门"的方向做判定，两个撞门方向共用同一套阈值
	var pass_dir: Vector2 = _resolve_pass_dir()
	# 接触盒必须比实体厚：实体一碰上，absorbent 材质就会把法向速度吃成 0
	var half_n: float = def.thickness * 0.5 + _ball.ball_radius + CONTACT_SLACK_PX
	var half_t: float = def.opening_width * 0.5 + _ball.ball_radius + 4.0
	var delta_pos: Vector2 = _ball.global_position - global_position
	var along_n: float = delta_pos.dot(pass_dir)
	var tangent: Vector2 = Vector2(-pass_dir.y, pass_dir.x)
	var along_t: float = delta_pos.dot(tangent)
	var touching: bool = absf(along_n) <= half_n and absf(along_t) <= half_t
	var inward: float = _ball.linear_velocity.dot(pass_dir)
	if not touching:
		_in_contact = false
		# 还没贴上：记下冲向门的速度与来向。真正重叠时当前速度往往已经被清成 0。
		var in_approach: bool = absf(along_n) < 220.0 and absf(along_t) < half_t + 48.0
		if in_approach and inward > 0.0:
			if inward > _approach_speed:
				_approach_speed = inward
				_approach_dir = pass_dir
		elif not in_approach:
			_approach_speed = 0.0
			_approach_dir = Vector2.ZERO
		return
	# 贴着门的每一帧都记宽限，冲击分类不会在接触列表空掉后变成普通墙
	_ball.mark_gate_contact()
	if _in_contact:
		return
	# 优先等球用撞前速度 notify_impact；本帧没通知再走接近速度兜底
	if not _judge_queued:
		_judge_queued = true
		call_deferred("_judge_if_still_pending")

## 球在物理步进后调用：pre_velocity 是上一帧速度，还没被 absorbent 门吃掉。
func notify_impact(pre_velocity: Vector2) -> void:
	if _state != GateState.CLOSED or def == null or _ball == null:
		return
	if _in_contact:
		return
	var pass_dir: Vector2 = _judge_dir()
	var impact_speed: float = maxf(pre_velocity.dot(pass_dir), _approach_speed)
	_commit_attempt(pass_dir, impact_speed)

## 本帧球没有撞上实体（只进了加厚接触盒）时，用接近速度判定并播半开。
func _judge_if_still_pending() -> void:
	_judge_queued = false
	if _state != GateState.CLOSED or _in_contact or _ball == null or def == null:
		return
	var pass_dir: Vector2 = _judge_dir()
	var inward: float = _ball.linear_velocity.dot(pass_dir)
	var impact_speed: float = maxf(inward, _approach_speed)
	_commit_attempt(pass_dir, impact_speed)

## 锁定本次接触并进入成败判定。
func _commit_attempt(pass_dir: Vector2, impact_speed: float) -> void:
	_in_contact = true
	_approach_speed = 0.0
	_approach_dir = Vector2.ZERO
	_pass_dir = pass_dir
	_evaluate_attempt(pass_dir, impact_speed)

func _evaluate_attempt(normal: Vector2, impact_speed: float = -1.0) -> void:
	# 测试可能直接调这里，保证动画方向也跟着本次判定方向
	_pass_dir = normal
	var window_s: float = def.window_s
	var now_us: int = Time.get_ticks_usec()
	var cutoff: int = now_us - int(window_s * 1_000_000.0)
	var samples: Array[Dictionary] = []
	for row: Dictionary in _force_history:
		if int(row["t_us"]) >= cutoff:
			samples.append(row)

	# 测试会直接改 linear_velocity 再调这里；正式游玩传入撞前接近速度
	var forward_speed: float = impact_speed
	if forward_speed < 0.0:
		forward_speed = _ball.linear_velocity.dot(normal)
	var impact_strength: float = maxf(0.0, forward_speed)

	var a_active: int = 0
	var b_active: int = 0
	var a_sum: Vector2 = Vector2.ZERO
	var b_sum: Vector2 = Vector2.ZERO
	var total: int = maxi(samples.size(), 1)
	const ACTIVE_EPS: float = 0.35
	for row: Dictionary in samples:
		var fa: Vector2 = row["a"] as Vector2
		var fb: Vector2 = row["b"] as Vector2
		if fa.length() >= ACTIVE_EPS:
			a_active += 1
			a_sum += fa
		if fb.length() >= ACTIVE_EPS:
			b_active += 1
			b_sum += fb

	var a_ratio: float = float(a_active) / float(total)
	var b_ratio: float = float(b_active) / float(total)
	var a_dir: Vector2 = a_sum.normalized() if a_sum.length() > 0.001 else Vector2.ZERO
	var b_dir: Vector2 = b_sum.normalized() if b_sum.length() > 0.001 else Vector2.ZERO
	var cosine: float = 0.0
	if a_dir != Vector2.ZERO and b_dir != Vector2.ZERO:
		cosine = a_dir.dot(b_dir)

	var combined: Vector2 = a_sum + b_sum
	var axis_align: float = 0.0
	if combined.length() > 0.001:
		axis_align = combined.normalized().dot(normal)

	var fail_reason: String = ""
	if forward_speed < def.speed_threshold:
		fail_reason = "speed_low"
	elif a_ratio < def.activity_ratio_min:
		fail_reason = "missing_A"
	elif b_ratio < def.activity_ratio_min:
		fail_reason = "missing_B"
	elif cosine < def.direction_cosine_min:
		fail_reason = "direction_conflict"
	elif axis_align < 0.35:
		fail_reason = "off_axis"

	var payload: Dictionary = {
		"gate_id": def.gate_id,
		"component_id": def.gate_id,
		"forward_speed": forward_speed,
		"impact_strength": impact_strength,
		"force_a_x": a_sum.x,
		"force_a_y": a_sum.y,
		"force_b_x": b_sum.x,
		"force_b_y": b_sum.y,
		"direction_cosine": cosine,
		"activity_a": a_ratio,
		"activity_b": b_ratio,
		"axis_align": axis_align,
		"damage": 0.0,
		"core_x": _ball.global_position.x,
		"core_y": _ball.global_position.y,
		"result_reason": fail_reason if fail_reason != "" else "opened",
		"note": "speed=%.1f cosine=%.2f dir=%s" % [forward_speed, cosine, _pass_dir_label()],
	}
	gate_attempt.emit(def.gate_id, payload)

	if fail_reason != "":
		payload["result_reason"] = fail_reason
		gate_failed.emit(def.gate_id, payload)
		var effort: float = _fail_open_effort(
			forward_speed, a_ratio, b_ratio, cosine, axis_align
		)
		_apply_fail_stop(normal, effort)
		return

	_begin_open(payload)

## 没撞开：先播半开，再刹掉冲向门的速度。
func _apply_fail_stop(normal: Vector2, effort: float) -> void:
	if _ball == null:
		return
	# 动画必须先播：冷却只挡物理连撞，不能把半开吃掉
	_play_fail_nudge(effort)
	if _stop_cooldown > 0.0:
		return
	_stop_cooldown = 0.22
	_absorb_inward_s = FAIL_ABSORB_S
	_ball.mark_gate_contact()
	var vel: Vector2 = _ball.linear_velocity
	var vn: float = vel.dot(normal)
	var vt: Vector2 = vel - normal * vn
	# 冲向门（vn>0）完全刹停；若已被引擎弹开，把离开速度压到微弱回弹
	var new_vn: float = 0.0
	if vn < 0.0:
		new_vn = maxf(vn, -FAIL_REBOUND_MAX)
	_ball.linear_velocity = vt * FAIL_TANGENT_KEEP + normal * new_vn
	_ball.angular_velocity *= FAIL_SPIN_KEEP
	var parent: Node = get_parent()
	if parent != null:
		GateBurst.play_hit(parent, global_position)

## 当前撞击离“能开门”有多近：0 几乎没碰到，1 已经顶在阈值上。
func _fail_open_effort(
	forward_speed: float,
	a_ratio: float,
	b_ratio: float,
	cosine: float,
	axis_align: float,
) -> float:
	var speed_ratio: float = clampf(forward_speed / maxf(def.speed_threshold, 1.0), 0.0, 1.0)
	var act_min: float = maxf(def.activity_ratio_min, 0.01)
	var a_t: float = clampf(a_ratio / act_min, 0.0, 1.0)
	var b_t: float = clampf(b_ratio / act_min, 0.0, 1.0)
	var cos_min: float = maxf(def.direction_cosine_min, 0.01)
	var cos_t: float = clampf((cosine + 1.0) * 0.5, 0.0, 1.0)
	if cosine > 0.0:
		cos_t = clampf(cosine / cos_min, 0.0, 1.0)
	var align_t: float = clampf(axis_align / 0.35, 0.0, 1.0)
	# 速度决定冲击感，合作质量决定会不会“快开了”
	var effort: float = speed_ratio * 0.62 + minf(a_t, b_t) * 0.22 + cos_t * 0.10 + align_t * 0.06
	return clampf(effort, 0.0, 1.0)

## 本次撞门方向的可读标签，写进事件日志的 note，便于分析区分两种撞法。
func _pass_dir_label() -> String:
	if absf(_pass_dir.x) >= absf(_pass_dir.y):
		return "L2R" if _pass_dir.x >= 0.0 else "R2L"
	return "T2B" if _pass_dir.y >= 0.0 else "B2T"

## 把两扇门叶还原到闭合姿态
func _reset_panels_pose() -> void:
	if _fail_tween != null and _fail_tween.is_valid():
		_fail_tween.kill()
	_fail_tween = null
	z_index = 0
	if _art_root != null:
		_art_root.position = Vector2.ZERO
		_art_root.rotation = 0.0
	if _visual_holder != null:
		_visual_holder.position = Vector2.ZERO
		_visual_holder.rotation = 0.0
	if _panel_left != null:
		_panel_left.position = _panel_left_rest
		_panel_left.rotation = 0.0
		_panel_left.modulate = Color.WHITE
	if _panel_right != null:
		_panel_right.position = _panel_right_rest
		_panel_right.rotation = 0.0
		_panel_right.modulate = Color.WHITE

## 失败：上下两扇绕铰链转开一道缝，整座门（含立柱）沿穿过方向让位，再弹簧弹回。
func _play_fail_nudge(effort: float) -> void:
	if _panel_left == null or _panel_right == null:
		return
	# 接触盒抖动会反复判定：正在播就不要杀 tween 重来，否则永远停在闭合
	if _fail_tween != null and _fail_tween.is_valid() and _fail_tween.is_running():
		return
	_reset_panels_pose()
	var amount: float = clampf(effort, 0.0, 1.0)
	# 失败只顶开一小缝，力度越大越接近 15°
	var angle: float = deg_to_rad(lerpf(FAIL_OPEN_ANGLE_MIN_DEG, FAIL_OPEN_ANGLE_MAX_DEG, amount))
	var kick: float = lerpf(3.0, FAIL_KICK_MAX, amount)
	var spread: float = lerpf(3.0, FAIL_SPREAD_MAX, amount)
	var open_dir: Vector2 = _pass_dir
	var sx: float = signf(open_dir.x)
	if sx == 0.0:
		sx = 1.0
	# 上扇 / 下扇反向旋转，对缝裂开，并沿撞击方向让位
	var left_rot: float = -sx * angle
	var right_rot: float = sx * angle
	var left_off: Vector2 = Vector2(sx * kick, -spread)
	var right_off: Vector2 = Vector2(sx * kick, spread)
	var flash: Color = Color(1.0, 1.0, 1.0).lerp(Color(1.22, 0.94, 0.62), amount)
	var open_s: float = lerpf(0.10, 0.16, amount)
	var close_s: float = lerpf(0.18, 0.26, amount)
	# 立柱只轻轻一晃，不要再叠一层大转角
	var jolt_rot: float = deg_to_rad(lerpf(1.0, 3.0, amount)) * sx
	z_index = 8
	_fail_tween = create_tween()
	_fail_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_fail_tween.set_parallel(true)
	_fail_tween.tween_property(_panel_left, "rotation", left_rot, open_s) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_right, "rotation", right_rot, open_s) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_left, "position", _panel_left_rest + left_off, open_s) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_right, "position", _panel_right_rest + right_off, open_s) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_visual_holder, "position", open_dir * kick, open_s) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _art_root != null:
		_fail_tween.tween_property(_art_root, "position", open_dir * kick * 0.55, open_s) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_fail_tween.tween_property(_art_root, "rotation", jolt_rot, open_s) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_left, "modulate", flash, open_s * 0.5)
	_fail_tween.tween_property(_panel_right, "modulate", flash, open_s * 0.5)
	# 顶开后停一拍再弹回，半开必须能看清
	_fail_tween.chain().tween_interval(0.14)
	_fail_tween.chain().set_parallel(true)
	_fail_tween.tween_property(_panel_left, "rotation", 0.0, close_s) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_right, "rotation", 0.0, close_s) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_left, "position", _panel_left_rest, close_s) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_right, "position", _panel_right_rest, close_s) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_visual_holder, "position", Vector2.ZERO, close_s) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _art_root != null:
		_fail_tween.tween_property(_art_root, "position", Vector2.ZERO, close_s) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_fail_tween.tween_property(_art_root, "rotation", 0.0, close_s) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fail_tween.tween_property(_panel_left, "modulate", Color.WHITE, close_s)
	_fail_tween.tween_property(_panel_right, "modulate", Color.WHITE, close_s)
	_fail_tween.chain().tween_callback(_on_fail_nudge_finished)

## 半开弹回结束后清掉 tween 引用
func _on_fail_nudge_finished() -> void:
	_fail_tween = null
	z_index = 0

## 失败后短暂吸收冲向门的法向速度，抵消球材质弹性。
func _absorb_inward_velocity() -> void:
	if _ball == null or def == null:
		return
	var reach: float = def.opening_width * 0.5 + _ball.ball_radius + 24.0
	if (_ball.global_position - global_position).length() > reach:
		return
	# 吸收的是"继续冲向门"的分量，方向必须用本次撞击解算出的穿门方向
	var normal: Vector2 = _pass_dir
	var vn: float = _ball.linear_velocity.dot(normal)
	if vn > 0.0:
		_ball.linear_velocity -= normal * vn
	elif vn < -FAIL_REBOUND_MAX:
		_ball.linear_velocity += normal * (-vn - FAIL_REBOUND_MAX)

func _begin_open(payload: Dictionary) -> void:
	_state = GateState.OPENING
	_absorb_inward_s = 0.0
	_reset_panels_pose()
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if _ball != null:
		_ball.mark_gate_contact()
		_apply_break_slowdown()
	var parent: Node = get_parent()
	if parent != null:
		GateBurst.play_break(parent, global_position)
	_fade_ground_shadow()
	_play_break_panels()
	gate_opened.emit(def.gate_id, payload)

## 撞碎木门吃掉九成冲量：穿过门本身就是成功，出来时几乎停住。
func _apply_break_slowdown() -> void:
	if _ball == null or def == null:
		return
	var normal: Vector2 = _pass_dir
	var vel: Vector2 = _ball.linear_velocity
	var vn: float = vel.dot(normal)
	var vt: Vector2 = vel - normal * vn
	var kept: float = vn * SUCCESS_SPEED_KEEP
	if vn > 0.0:
		kept = maxf(kept, SUCCESS_MIN_THROUGH)
	_ball.linear_velocity = vt * 0.20 + normal * kept
	_ball.angular_velocity *= 0.20

## 撞开后门影淡掉，石柱还在
func _fade_ground_shadow() -> void:
	if _ground_shadow == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(_ground_shadow, "modulate:a", 0.0, 0.28)

## 成功：上下两扇顺着球的穿门方向朝外倒下并淡出。
## 门叶铰链在上/下柱，绕轴转开的朝向必须跟随撞击方向镜像，否则会朝球脸上开。
func _play_break_panels() -> void:
	var sx: float = signf(_pass_dir.x)
	if sx == 0.0:
		sx = 1.0
	# 沿穿门方向轻微前推 + 沿开口方向分别向两端甩开
	_fall_panel(_panel_left, Vector2(sx * 10.0, -24.0), deg_to_rad(-105.0) * sx)
	_fall_panel(_panel_right, Vector2(sx * 10.0, 24.0), deg_to_rad(105.0) * sx)

func _fall_panel(panel: Node2D, offset: Vector2, rot: float) -> void:
	if panel == null:
		return
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "position", panel.position + offset, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "rotation", rot, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(func() -> void:
		_state = GateState.OPENED
		panel.visible = false
	)

func is_opened() -> bool:
	return _state == GateState.OPENED or _state == GateState.OPENING
