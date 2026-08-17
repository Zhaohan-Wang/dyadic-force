extends Control
## 双人校准引导页：左右玩家各自拥有独立卡片。
## 手柄玩家依次完成「静置 3 秒」和「左摇杆绕圈」；键盘玩家明确显示无需校准。

enum Phase {
	REST,    ## 静置测漂移
	CIRCLE,  ## 绕圈验证
	DONE,    ## 全部通过，可继续
	FAILED,  ## 漂移超限，需重试或重连
}

enum GuideMode {
	KEYBOARD,
	REST,
	WAIT,
	CIRCLE,
	READY,
	FAILED,
}

## 静置时长（秒）
const REST_SECONDS: float = 3.0
## 任一轴最大绝对漂移阈值（实验协议 §6.3）
const DRIFT_LIMIT: float = 0.08
## 绕圈时最大径向值下限
const CIRCLE_MIN_RADIAL: float = 0.90
## 八个角度扇区各覆盖一次才算绕圈完整
const SECTOR_COUNT: int = 8
## 记入扇区所需的最小径向
const SECTOR_MIN_RADIAL: float = 0.55

const TEX_XBOX: Texture2D = preload("res://assets/ui/controller_xbox_guide.png")
const TEX_SWITCH: Texture2D = preload("res://assets/ui/controller_switch_guide.png")
const TEX_PLAYSTATION: Texture2D = preload("res://assets/ui/controller_playstation_guide.png")

## 单个玩家卡片的节点引用。
class PlayerCard:
	var root: Control
	var panel: NinePatchRect
	var player_label: Label
	var device_label: Label
	var controller_backdrop: Panel
	var controller_image: TextureRect
	var keyboard_row: HBoxContainer
	var guide: StickGuide
	var action_label: Label
	var detail_label: Label
	var badge: Label

## 左摇杆动态图：展示禁止操作、实时位置、八向覆盖和完成状态。
class StickGuide:
	extends Control

	var mode: GuideMode = GuideMode.WAIT
	var raw_stick: Vector2 = Vector2.ZERO
	var sector_mask: int = 0
	var pulse: float = 0.0

	func _process(delta: float) -> void:
		pulse += delta
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.34
		var ink: Color = MenuKit.COL_INK
		var muted: Color = Color(ink, 0.28)
		var ready: Color = MenuKit.COL_READY
		var warning: Color = MenuKit.COL_DANGER

		# 摇杆活动范围与十字参考线。
		draw_circle(center, radius, Color(0.12, 0.09, 0.06, 0.08))
		draw_arc(center, radius, 0.0, TAU, 64, Color(ink, 0.62), 5.0)
		draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), muted, 2.0)
		draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), muted, 2.0)

		match mode:
			GuideMode.REST:
				_draw_rest(center, radius, warning)
			GuideMode.CIRCLE:
				_draw_circle_progress(center, radius, ready, ink)
			GuideMode.READY, GuideMode.KEYBOARD:
				_draw_ready(center, radius, ready)
			GuideMode.FAILED:
				_draw_failed(center, radius, warning)
			GuideMode.WAIT:
				_draw_wait(center, radius, muted)

	## 静置状态：摇杆固定在中心并用醒目叉号禁止操作。
	func _draw_rest(center: Vector2, radius: float, color: Color) -> void:
		var glow: float = 0.72 + sin(pulse * 5.0) * 0.18
		draw_circle(center, radius * 0.24, Color(MenuKit.COL_INK, 0.88))
		draw_arc(center, radius * 0.43, 0.0, TAU, 32, Color(color, glow), 8.0)
		var arm: float = radius * 0.72
		draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm), color, 10.0)
		draw_line(center + Vector2(-arm, arm), center + Vector2(arm, -arm), color, 10.0)

	## 绕圈状态：高亮已覆盖扇区，并显示摇杆实时位置。
	func _draw_circle_progress(
		center: Vector2,
		radius: float,
		ready_color: Color,
		ink: Color,
	) -> void:
		for sector: int in SECTOR_COUNT:
			var start: float = -PI + float(sector) * TAU / float(SECTOR_COUNT)
			var finish: float = start + TAU / float(SECTOR_COUNT) - 0.035
			var covered: bool = (sector_mask & (1 << sector)) != 0
			var color: Color = ready_color if covered else Color(ink, 0.18)
			draw_arc(center, radius * 1.08, start, finish, 12, color, 11.0)
		var clamped: Vector2 = raw_stick.limit_length(1.0)
		var knob: Vector2 = center + clamped * radius
		draw_line(center, knob, Color(MenuKit.COL_ACCENT, 0.55), 6.0)
		draw_circle(knob, radius * 0.17, MenuKit.COL_ACCENT)
		draw_circle(knob, radius * 0.09, Color.WHITE)

	## 完成状态：绿色勾号。
	func _draw_ready(center: Vector2, radius: float, color: Color) -> void:
		draw_arc(center, radius * 0.72, 0.0, TAU, 48, Color(color, 0.95), 8.0)
		var points: PackedVector2Array = PackedVector2Array([
			center + Vector2(-radius * 0.42, 0.0),
			center + Vector2(-radius * 0.12, radius * 0.32),
			center + Vector2(radius * 0.48, -radius * 0.38),
		])
		draw_polyline(points, color, 12.0)

	## 失败状态：漂移摇杆位置与红色警告环。
	func _draw_failed(center: Vector2, radius: float, color: Color) -> void:
		draw_arc(center, radius * 0.78, 0.0, TAU, 48, color, 10.0)
		var knob: Vector2 = center + raw_stick.limit_length(1.0) * radius
		draw_circle(knob, radius * 0.17, color)
		draw_line(center + Vector2(-radius * 0.4, -radius * 0.4),
			center + Vector2(radius * 0.4, radius * 0.4), color, 10.0)
		draw_line(center + Vector2(-radius * 0.4, radius * 0.4),
			center + Vector2(radius * 0.4, -radius * 0.4), color, 10.0)

	## 等待另一位玩家时保持中性。
	func _draw_wait(center: Vector2, radius: float, color: Color) -> void:
		draw_circle(center, radius * 0.2, color)
		for i: int in 3:
			var x: float = (float(i) - 1.0) * radius * 0.38
			draw_circle(center + Vector2(x, radius * 0.72), radius * 0.07, color)

var _phase: Phase = Phase.REST
var _phase_banner: ColorRect
var _phase_title: Label
var _phase_instruction: Control
var _step_label: Control
var _cards: Array[PlayerCard] = []
var _continue_btn: Button
var _retry_btn: Button

## 静置采样：joy_id → 累计 sum / 样本数 / 最大 |axis|
var _rest_sum: Dictionary[int, Vector2] = {}
var _rest_count: Dictionary[int, int] = {}
var _rest_drift: Dictionary[int, float] = {}
var _rest_left: float = REST_SECONDS

## 绕圈：joy_id → 最大径向、扇区位图
var _circle_max: Dictionary[int, float] = {}
var _circle_mask: Dictionary[int, int] = {}
var _circle_joy_ids: Array[int] = []
var _circle_index: int = 0

func _ready() -> void:
	_build()
	InputHub.joy_hotplug.connect(_on_hotplug)
	if InputHub.has_joypad_joined():
		_begin_rest()
	else:
		# 纯键盘组合也保留说明页，让玩家明确知道无需校准。
		_finish_ok()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	var title: Control = MenuKit.make_pixel_outline_text(
		GameState.ui("输入检测", "INPUT CHECK"), 40, MenuKit.COL_CREAM, 3
	)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-420, 34)
	title.size = Vector2(840, 64)
	add_child(title)

	_step_label = MenuKit.make_world_caption(GameState.ui("步骤 1 / 2", "STEP 1 / 2"), 24)
	_step_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_step_label.position = Vector2(-260, 96)
	_step_label.size = Vector2(520, 30)
	add_child(_step_label)

	# 当前阶段占据标题下方整条横幅，避免指令淹没在设备信息里。
	_phase_banner = ColorRect.new()
	_phase_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_banner.position = Vector2(-670, 132)
	_phase_banner.size = Vector2(1340, 108)
	_phase_banner.color = Color(MenuKit.COL_DANGER, 0.94)
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_banner)

	_phase_title = MenuKit.make_title_label(
		GameState.ui("请勿操作！", "HANDS OFF!"), 34, MenuKit.COL_CREAM, true
	)
	_phase_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_title.position = Vector2(-650, 144)
	_phase_title.size = Vector2(1300, 44)
	add_child(_phase_title)

	_phase_instruction = MenuKit.make_pixel_outline_text(
		GameState.ui("请放下手柄，不要触碰左摇杆。", "PUT THE CONTROLLER DOWN. DO NOT TOUCH THE LEFT STICK."),
		24,
		MenuKit.COL_CREAM,
		2,
	)
	_phase_instruction.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_instruction.position = Vector2(-650, 193)
	_phase_instruction.size = Vector2(1300, 34)
	add_child(_phase_instruction)

	# 左右双卡，与配对页一致地保持 P1/P2 空间归属。
	var cards_row: HBoxContainer = HBoxContainer.new()
	cards_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	cards_row.position = Vector2(-790, 270)
	cards_row.custom_minimum_size = Vector2(1580, 620)
	cards_row.add_theme_constant_override("separation", 40)
	add_child(cards_row)
	for slot: int in 2:
		var card: PlayerCard = _make_player_card(slot)
		_cards.append(card)
		cards_row.add_child(card.root)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	actions.position = Vector2(-300, -120)
	actions.custom_minimum_size = Vector2(600, 96)
	add_child(actions)

	_retry_btn = MenuKit.make_big_button(GameState.ui("重试", "RETRY"), 30, Vector2(250, 90))
	_retry_btn.pressed.connect(_begin_rest)
	_retry_btn.visible = false
	actions.add_child(_retry_btn)

	_continue_btn = MenuKit.make_big_button(GameState.ui("继续", "CONTINUE"), 30, Vector2(290, 90))
	_continue_btn.pressed.connect(_go_guide)
	_continue_btn.visible = false
	actions.add_child(_continue_btn)

	var back_row: HBoxContainer = MenuKit.make_device_hint_row(
		["ESC"],
		["b"],
		GameState.ui("返回", "BACK"),
		44.0,
		InputHub.session_profile(),
	)
	back_row.position = Vector2(40, 36)
	add_child(back_row)

## 构建单个玩家校准卡：设备图、动态图和一句明确动作指令。
func _make_player_card(slot: int) -> PlayerCard:
	var card: PlayerCard = PlayerCard.new()
	card.root = Control.new()
	card.root.custom_minimum_size = Vector2(770, 600)

	card.panel = MenuKit.make_panel(Vector2(770, 600))
	card.panel.size = Vector2(770, 600)
	card.root.add_child(card.panel)

	card.player_label = MenuKit.make_title_label(
		"P%d" % (slot + 1),
		28,
		MenuKit.COL_INK if slot == 0 else MenuKit.COL_ACCENT,
		true,
	)
	card.player_label.position = Vector2(28, 24)
	card.player_label.size = Vector2(110, 42)
	card.panel.add_child(card.player_label)

	card.device_label = MenuKit.make_panel_label("", 26, 0.78)
	card.device_label.position = Vector2(140, 30)
	card.device_label.size = Vector2(590, 34)
	card.device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.panel.add_child(card.device_label)

	card.controller_backdrop = Panel.new()
	card.controller_backdrop.position = Vector2(45, 78)
	card.controller_backdrop.size = Vector2(300, 190)
	card.controller_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var controller_style: StyleBoxFlat = StyleBoxFlat.new()
	controller_style.bg_color = Color(MenuKit.COL_CREAM, 0.82)
	controller_style.border_color = Color(MenuKit.COL_INK, 0.34)
	controller_style.set_border_width_all(3)
	controller_style.set_corner_radius_all(18)
	card.controller_backdrop.add_theme_stylebox_override("panel", controller_style)
	card.panel.add_child(card.controller_backdrop)

	card.controller_image = TextureRect.new()
	card.controller_image.position = Vector2(45, 78)
	card.controller_image.size = Vector2(300, 190)
	card.controller_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.controller_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.controller_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.controller_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.panel.add_child(card.controller_image)

	card.keyboard_row = HBoxContainer.new()
	card.keyboard_row.position = Vector2(62, 126)
	card.keyboard_row.custom_minimum_size = Vector2(270, 100)
	card.keyboard_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.keyboard_row.add_theme_constant_override("separation", 8)
	card.panel.add_child(card.keyboard_row)

	card.guide = StickGuide.new()
	card.guide.position = Vector2(400, 80)
	card.guide.size = Vector2(300, 280)
	card.guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.panel.add_child(card.guide)

	card.action_label = MenuKit.make_title_label("", 36, MenuKit.COL_ACCENT, true)
	card.action_label.position = Vector2(34, 374)
	card.action_label.size = Vector2(702, 58)
	card.panel.add_child(card.action_label)

	card.detail_label = MenuKit.make_panel_label("", 26, 0.82)
	card.detail_label.position = Vector2(42, 436)
	card.detail_label.size = Vector2(686, 82)
	card.detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.panel.add_child(card.detail_label)

	card.badge = MenuKit.make_label("", 22, MenuKit.COL_CREAM, 0)
	card.badge.position = Vector2(170, 528)
	card.badge.size = Vector2(430, 46)
	card.badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.panel.add_child(card.badge)

	_setup_card_device(card, slot)
	return card

## 根据槽位来源选择手柄配图；键盘明确显示“不需要校准”。
func _setup_card_device(card: PlayerCard, slot: int) -> void:
	var kind: InputHub.SourceKind = InputHub.slot_kind(slot)
	if kind != InputHub.SourceKind.JOYPAD:
		MenuKit.set_label_text(card.device_label, GameState.ui("键盘", "KEYBOARD"))
		card.controller_backdrop.visible = false
		card.controller_image.visible = false
		card.keyboard_row.visible = true
		var keys: Array[String] = ["W", "A", "S", "D"]
		if kind == InputHub.SourceKind.KEYBOARD_ARROWS:
			keys = ["UP", "LEFT", "DOWN", "RIGHT"]
		for key: String in keys:
			card.keyboard_row.add_child(MenuKit.make_key_icon(key, 54.0))
		card.guide.mode = GuideMode.KEYBOARD
		_set_card_copy(
			card,
			GameState.ui("无需校准", "NO CALIBRATION NEEDED"),
			GameState.ui(
				"键盘是数字输入，不存在摇杆漂移。该玩家已准备。",
				"Keyboard input is digital and has no stick drift. This player is ready.",
			),
		)
		_set_badge(card, GameState.ui("已准备", "READY"), MenuKit.COL_READY)
		return

	var joy_id: int = InputHub.slot_joy_id(slot)
	var joy_name: String = Input.get_joy_name(joy_id)
	MenuKit.set_label_text(
		card.device_label,
		GameState.ui(
			"手柄 %d" % (joy_id + 1),
			joy_name.to_upper() if joy_name != "" else "GAMEPAD %d" % (joy_id + 1),
		),
	)
	card.controller_image.visible = true
	card.controller_backdrop.visible = true
	card.keyboard_row.visible = false
	card.controller_image.texture = _controller_texture(joy_id)
	card.guide.mode = GuideMode.WAIT
	_set_card_copy(
		card,
		GameState.ui("等待检测", "WAITING FOR CHECK"),
		GameState.ui(
			"请按照上方的大字提示操作；本次只检测左摇杆。",
			"Follow the large instruction above. Only the LEFT STICK is checked.",
		),
	)
	_set_badge(card, GameState.ui("等待", "WAIT"), Color("7c6b5c"))

## 依据设备名称选取资源包中的对应控制器图。
func _controller_texture(joy_id: int) -> Texture2D:
	if InputHub.is_nintendo_joypad(joy_id):
		return TEX_SWITCH
	var name: String = Input.get_joy_name(joy_id).to_lower()
	if (
		name.contains("dual")
		or name.contains("playstation")
		or name.contains("sony")
		or name.contains("ps4")
		or name.contains("ps5")
	):
		return TEX_PLAYSTATION
	return TEX_XBOX

func _process(delta: float) -> void:
	_update_live_guides()
	match _phase:
		Phase.REST:
			_tick_rest(delta)
		Phase.CIRCLE:
			_tick_circle()
		_:
			pass

## 每帧把真实左摇杆位置推给对应动态图。
func _update_live_guides() -> void:
	for slot: int in 2:
		if InputHub.slot_kind(slot) != InputHub.SourceKind.JOYPAD:
			continue
		var joy_id: int = InputHub.slot_joy_id(slot)
		var raw: Vector2 = InputHub.read_raw_stick(joy_id)
		_cards[slot].guide.raw_stick = raw - InputHub.get_center_offset(joy_id)
		_cards[slot].guide.sector_mask = _circle_mask.get(joy_id, 0)

func _begin_rest() -> void:
	_phase = Phase.REST
	_rest_left = REST_SECONDS
	_rest_sum.clear()
	_rest_count.clear()
	_rest_drift.clear()
	_continue_btn.visible = false
	_retry_btn.visible = false
	MenuKit.set_pixel_outline_text(
		_step_label, GameState.ui("步骤 1 / 2 · 中心检测", "STEP 1 / 2  -  CENTER CHECK")
	)
	_set_phase_banner(
		GameState.ui("请勿操作！ %.1f 秒" % REST_SECONDS, "HANDS OFF!  %.1f s" % REST_SECONDS),
		GameState.ui("请放下手柄，不要触碰左摇杆。", "PUT THE CONTROLLER DOWN. DO NOT TOUCH THE LEFT STICK."),
		MenuKit.COL_DANGER,
	)
	for joy_id: int in InputHub.joined_joy_ids():
		InputHub.clear_joy_calibration(joy_id)
		_rest_sum[joy_id] = Vector2.ZERO
		_rest_count[joy_id] = 0
		_rest_drift[joy_id] = 0.0
	for slot: int in 2:
		if InputHub.slot_kind(slot) == InputHub.SourceKind.JOYPAD:
			var card: PlayerCard = _cards[slot]
			card.guide.mode = GuideMode.REST
			_set_card_copy(
				card,
				GameState.ui("不要移动摇杆", "DO NOT MOVE THE STICK"),
				GameState.ui(
					"请完全松开手柄，我们正在测量摇杆的中心位置。",
					"Release the controller completely. We are measuring its neutral center.",
				),
			)
			_set_badge(card, GameState.ui("请勿操作", "HANDS OFF"), MenuKit.COL_DANGER)

func _tick_rest(delta: float) -> void:
	_rest_left = maxf(0.0, _rest_left - delta)
	_set_phase_banner(
		GameState.ui("请勿操作！ %.1f 秒" % _rest_left, "HANDS OFF!  %.1f s" % _rest_left),
		GameState.ui("请放下手柄，不要触碰左摇杆。", "PUT THE CONTROLLER DOWN. DO NOT TOUCH THE LEFT STICK."),
		MenuKit.COL_DANGER,
	)
	for joy_id: int in InputHub.joined_joy_ids():
		var raw: Vector2 = InputHub.read_raw_stick(joy_id)
		_rest_sum[joy_id] = _rest_sum.get(joy_id, Vector2.ZERO) + raw
		_rest_count[joy_id] = _rest_count.get(joy_id, 0) + 1
		_rest_drift[joy_id] = maxf(
			_rest_drift.get(joy_id, 0.0),
			maxf(absf(raw.x), absf(raw.y)),
		)
	if _rest_left > 0.0:
		return
	var failed: bool = false
	for joy_id: int in InputHub.joined_joy_ids():
		var count: int = maxi(_rest_count.get(joy_id, 0), 1)
		var center: Vector2 = _rest_sum.get(joy_id, Vector2.ZERO) / float(count)
		var drift: float = _rest_drift.get(joy_id, 0.0)
		InputHub.set_joy_rest_calibration(joy_id, center, drift)
		if drift > DRIFT_LIMIT:
			failed = true
	if failed:
		_show_rest_failure()
	else:
		_begin_circle()

func _show_rest_failure() -> void:
	_phase = Phase.FAILED
	AudioHub.play_ui_error()
	MenuKit.set_pixel_outline_text(
		_step_label, GameState.ui("中心检测失败", "CENTER CHECK FAILED")
	)
	_set_phase_banner(
		GameState.ui("检测到摇杆移动", "STICK WAS MOVED"),
		GameState.ui(
			"请松开摇杆；如果仍然漂移，请重新连接手柄。",
			"RELEASE THE STICK. IF IT STILL DRIFTS, RECONNECT THE CONTROLLER.",
		),
		MenuKit.COL_DANGER,
	)
	_retry_btn.visible = true
	_retry_btn.grab_focus.call_deferred()
	for slot: int in 2:
		if InputHub.slot_kind(slot) != InputHub.SourceKind.JOYPAD:
			continue
		var joy_id: int = InputHub.slot_joy_id(slot)
		var drift: float = _rest_drift.get(joy_id, 0.0)
		var card: PlayerCard = _cards[slot]
		card.guide.mode = GuideMode.FAILED
		_set_card_copy(
			card,
			GameState.ui("中心检测失败", "CENTER CHECK FAILED"),
			GameState.ui(
				"检测漂移 %.3f（上限 %.2f）。请松开摇杆后重试。" % [drift, DRIFT_LIMIT],
				"Measured drift %.3f (limit %.2f). Release the stick and retry." % [drift, DRIFT_LIMIT],
			),
		)
		_set_badge(card, GameState.ui("重试", "RETRY"), MenuKit.COL_DANGER)

func _begin_circle() -> void:
	_phase = Phase.CIRCLE
	AudioHub.play_ui_ready()
	_circle_joy_ids = InputHub.joined_joy_ids()
	_circle_index = 0
	_circle_max.clear()
	_circle_mask.clear()
	for joy_id: int in _circle_joy_ids:
		_circle_max[joy_id] = 0.0
		_circle_mask[joy_id] = 0
	MenuKit.set_pixel_outline_text(
		_step_label, GameState.ui("步骤 2 / 2 · 范围检测", "STEP 2 / 2  -  RANGE CHECK")
	)
	_set_phase_banner(
		GameState.ui("移动左摇杆", "MOVE THE LEFT STICK"),
		GameState.ui("将摇杆推到边缘，然后沿边缘完整绕一圈。", "PUSH IT TO THE EDGE, THEN TRACE ONE FULL CIRCLE."),
		MenuKit.COL_ACCENT,
	)
	_refresh_circle_cards()

func _tick_circle() -> void:
	if _circle_joy_ids.is_empty():
		_finish_ok()
		return
	var joy_id: int = _circle_joy_ids[_circle_index]
	var raw: Vector2 = InputHub.read_raw_stick(joy_id)
	var calibrated: Vector2 = raw - InputHub.get_center_offset(joy_id)
	var m: float = calibrated.length()
	_circle_max[joy_id] = maxf(_circle_max.get(joy_id, 0.0), m)
	if m >= SECTOR_MIN_RADIAL:
		var angle: float = atan2(calibrated.y, calibrated.x)
		var sector: int = int(floor((angle + PI) / (TAU / float(SECTOR_COUNT)))) % SECTOR_COUNT
		_circle_mask[joy_id] = _circle_mask.get(joy_id, 0) | (1 << sector)
	_refresh_circle_cards()
	var full_mask: int = (1 << SECTOR_COUNT) - 1
	if (
		_circle_max.get(joy_id, 0.0) >= CIRCLE_MIN_RADIAL
		and _circle_mask.get(joy_id, 0) == full_mask
	):
		InputHub.mark_joy_circle_passed(joy_id, _circle_max.get(joy_id, 0.0))
		HapticHub.confirm_calibration(joy_id)
		_circle_index += 1
		if _circle_index >= _circle_joy_ids.size():
			_finish_ok()
		else:
			AudioHub.play_ui_ready()
			_refresh_circle_cards()

## 更新左右卡片：当前手柄高亮操作，另一个手柄明确等待。
func _refresh_circle_cards() -> void:
	if _circle_index >= _circle_joy_ids.size():
		return
	var active_joy: int = _circle_joy_ids[_circle_index]
	var active_slot: int = InputHub.find_joypad_slot(active_joy)
	_set_phase_banner(
		GameState.ui(
			"P%d · 移动左摇杆" % (active_slot + 1),
			"P%d - MOVE THE LEFT STICK" % (active_slot + 1),
		),
		GameState.ui("将摇杆推到边缘，然后沿边缘完整绕一圈。", "PUSH IT TO THE EDGE, THEN TRACE ONE FULL CIRCLE."),
		MenuKit.COL_ACCENT,
	)
	for slot: int in 2:
		if InputHub.slot_kind(slot) != InputHub.SourceKind.JOYPAD:
			continue
		var joy_id: int = InputHub.slot_joy_id(slot)
		var card: PlayerCard = _cards[slot]
		if InputHub.is_joy_calibrated(joy_id):
			card.guide.mode = GuideMode.READY
			_set_card_copy(
				card,
				GameState.ui("校准完成", "CALIBRATION COMPLETE"),
				GameState.ui(
					"此手柄已准备，请等待另一名玩家。",
					"This controller is ready. Wait for the other player.",
				),
			)
			_set_badge(card, GameState.ui("已准备", "READY"), MenuKit.COL_READY)
		elif joy_id == active_joy:
			var mask: int = _circle_mask.get(joy_id, 0)
			var sectors: int = _count_sectors(mask)
			var max_r: float = _circle_max.get(joy_id, 0.0)
			card.guide.mode = GuideMode.CIRCLE
			_set_card_copy(
				card,
				GameState.ui("沿外圈绕一圈", "TRACE THE OUTER EDGE"),
				GameState.ui(
					"已覆盖 %d/%d 个方向 · 最大范围 %.2f/%.2f" % [
						sectors, SECTOR_COUNT, max_r, CIRCLE_MIN_RADIAL,
					],
					"Covered %d/%d directions   Max reach %.2f/%.2f" % [
						sectors, SECTOR_COUNT, max_r, CIRCLE_MIN_RADIAL,
					],
				),
			)
			_set_badge(card, GameState.ui("轮到你", "YOUR TURN"), MenuKit.COL_ACCENT)
		else:
			card.guide.mode = GuideMode.WAIT
			_set_card_copy(
				card,
				GameState.ui("等待轮到你", "WAIT FOR YOUR TURN"),
				GameState.ui(
					"另一只手柄检测期间，请保持摇杆居中。",
					"Keep your stick centered while the other controller is checked.",
				),
			)
			_set_badge(card, GameState.ui("等待", "WAIT"), Color("7c6b5c"))

func _count_sectors(mask: int) -> int:
	var count: int = 0
	for i: int in SECTOR_COUNT:
		if (mask & (1 << i)) != 0:
			count += 1
	return count

func _finish_ok() -> void:
	_phase = Phase.DONE
	AudioHub.play_ui_ready()
	MenuKit.set_pixel_outline_text(
		_step_label, GameState.ui("输入检测完成", "INPUT CHECK COMPLETE")
	)
	_set_phase_banner(
		GameState.ui("所有玩家已准备", "ALL PLAYERS READY"),
		GameState.ui(
			"手柄已完成校准；键盘玩家无需校准。",
			"Controllers are calibrated. Keyboard players need no calibration.",
		),
		MenuKit.COL_READY,
	)
	_continue_btn.visible = true
	_continue_btn.grab_focus.call_deferred()
	for slot: int in 2:
		var card: PlayerCard = _cards[slot]
		card.guide.mode = GuideMode.READY
		if InputHub.slot_kind(slot) == InputHub.SourceKind.JOYPAD:
			_set_card_copy(
				card,
				GameState.ui("校准完成", "CALIBRATION COMPLETE"),
				GameState.ui(
					"中心位置和完整移动范围均已通过。",
					"Center and full movement range passed.",
				),
			)
		else:
			_set_card_copy(
				card,
				GameState.ui("无需校准", "NO CALIBRATION NEEDED"),
				GameState.ui(
					"键盘是数字输入，该玩家已准备。",
					"Keyboard input is digital. This player is ready.",
				),
			)
		_set_badge(card, GameState.ui("已准备", "READY"), MenuKit.COL_READY)

func _set_phase_banner(title: String, instruction: String, color: Color) -> void:
	_phase_banner.color = Color(color, 0.94)
	MenuKit.set_label_text(_phase_title, title, true)
	MenuKit.set_pixel_outline_text(_phase_instruction, instruction)

## 更新卡片动态文案并同步中英文字体。
func _set_card_copy(card: PlayerCard, action: String, detail: String) -> void:
	MenuKit.set_label_text(card.action_label, action, true)
	MenuKit.set_label_text(card.detail_label, detail)

func _set_badge(card: PlayerCard, text: String, color: Color) -> void:
	MenuKit.set_label_text(card.badge, text)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	card.badge.add_theme_stylebox_override("normal", style)

func _go_guide() -> void:
	if not InputHub.all_joined_joypads_calibrated() and InputHub.has_joypad_joined():
		return
	SceneDirector.go_to("res://scenes/guide_screen.tscn")

func _on_hotplug(_device_id: int, _connected: bool) -> void:
	# 热插拔会改变卡片归属，回配对页最清楚且不会保留错误校准。
	AudioHub.play_ui_error()
	SceneDirector.go_to("res://scenes/pairing_screen.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		SceneDirector.go_to("res://scenes/pairing_screen.tscn")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputHub.UI_CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		SceneDirector.go_to("res://scenes/pairing_screen.tscn")
	elif event.is_action_pressed(InputHub.UI_ACCEPT_ACTION):
		get_viewport().set_input_as_handled()
		if _phase == Phase.DONE:
			_go_guide()
		elif _phase == Phase.FAILED:
			_begin_rest()
