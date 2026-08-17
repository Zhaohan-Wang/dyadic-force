extends Control
## 玩家配对界面：两个槽位默认为空，必须由玩家主动按键加入。
##
## 交互规则：
## - P1 按 WASD 任意键加入；P2 按方向键任意键加入
## - 手柄按 A 认领第一个空槽位
## - 退出：P1 键盘按 X、P2 键盘按 DEL、手柄按 B
## - 双方都加入后 START 才可用（Enter / 手柄 A / 点击）
## - ESC 返回实验录入；未加入的手柄按 B 返回实验录入；手柄拔出时对应槽位自动腾空

## 每张槽位卡的节点引用集合
class SlotCard:
	var monkey: AnimatedSprite2D        ## 猴子形象（未加入时是剪影）
	var empty_box: Control              ## "如何加入"提示区
	var joined_box: Control             ## 已加入信息区
	var device_label: Label             ## 设备名
	var leave_hint: HBoxContainer       ## 退出方式提示
	var spring: UiSpring                ## 卡片弹簧（加入时 punch）

var _cards: Array[SlotCard] = []
var _start_btn: Button
var _start_hint: Control
var _toast: Control
var _toast_tween: Tween = null
## 左上返回提示；槽位变化后按当前双人设备组合重建。
var _back_hint_holder: HBoxContainer
## 最近一次槽位变化时间（防止加入的 A 键立刻触发开始）
var _slots_changed_ms: int = 0

func _ready() -> void:
	_build()
	InputHub.slots_changed.connect(_refresh)
	InputHub.joy_hotplug.connect(_on_hotplug)
	_refresh()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	# 页面标题统一用街机粗方块字（Press Start 2P）
	var title: Control = MenuKit.make_pixel_outline_text(
		GameState.ui("玩家配对", "PAIR UP"), 40, MenuKit.COL_CREAM, 3
	)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 64)
	title.size = Vector2(800, 72)
	add_child(title)
	UiSpring.attach(title, 0.5, 0.3).pop_in(0.02)

	# 副标题：告诉玩家门槛，字号/透明度都压在主标题之下
	var sub: Control = MenuKit.make_world_caption(
		GameState.ui("两名玩家都加入后才能开始", "BOTH PLAYERS MUST JOIN TO START"), 28
	)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-400, 152)
	sub.size = Vector2(800, 40)
	add_child(sub)
	UiSpring.attach(sub, 0.5, 0.25).pop_in(0.1)

	# ---- 两张槽位卡 ----
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	row.position = Vector2(-610, 230)
	row.custom_minimum_size = Vector2(1220, 500)
	row.add_theme_constant_override("separation", 60)
	add_child(row)
	for slot: int in 2:
		var card: Control = _make_slot_card(slot)
		row.add_child(card)

	# ---- START 与提示 ----
	_start_btn = MenuKit.make_big_button(
		GameState.ui("开始", "START"), 32, Vector2(440, 108)
	)
	_start_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_btn.position = Vector2(-220, -232)
	_start_btn.pressed.connect(_on_start)
	add_child(_start_btn)
	UiSpring.attach(_start_btn, 0.45, 0.3).pop_in(0.3)

	_start_hint = MenuKit.make_pixel_outline_text(
		GameState.ui("等待玩家加入…", "WAITING FOR PLAYERS..."),
		28,
		Color(1, 1, 1, 0.7),
		2,
	)
	_start_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_hint.position = Vector2(-400, -108)
	_start_hint.size = Vector2(800, 40)
	add_child(_start_hint)

	# ---- 返回提示（左上角） ----
	_back_hint_holder = HBoxContainer.new()
	_back_hint_holder.position = Vector2(40, 36)
	add_child(_back_hint_holder)
	_refresh_back_hint()

	# ---- 顶部通知条 ----
	_toast = MenuKit.make_pixel_outline_text(
		GameState.ui("通知", "NOTICE"), 28, MenuKit.COL_CREAM, 2
	)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-500, -56)
	_toast.size = Vector2(1000, 40)
	_toast.modulate.a = 0.0
	add_child(_toast)

## 组装一张槽位卡（含空/已加入两套内容，按状态切换显示）
func _make_slot_card(slot: int) -> Control:
	var panel: NinePatchRect = MenuKit.make_panel(Vector2(580, 490))
	var card: SlotCard = SlotCard.new()
	card.spring = UiSpring.attach(panel, 0.5, 0.3)
	card.spring.pop_in(0.15 + float(slot) * 0.1)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40.0
	box.offset_right = -40.0
	box.offset_top = 32.0
	box.offset_bottom = -32.0
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# 去标识化参与者、设备槽位与画面侧别必须同时可核对。
	var participant_letter: String = GameState.participant_letter_for_slot(slot)
	var participant_id: String = GameState.participant_id_for_slot(slot)
	var identity_text: String = GameState.ui(
		"参与者 %s · %s · P%d · %s" % [
			participant_letter,
			participant_id if not participant_id.is_empty() else "—",
			slot + 1,
			GameState.screen_side_for_slot(slot),
		],
		"PARTICIPANT %s · %s · P%d · %s" % [
			participant_letter,
			participant_id if not participant_id.is_empty() else "—",
			slot + 1,
			GameState.screen_side_for_slot(slot),
		],
	)
	var header: Label = MenuKit.make_label(
		identity_text, 26,
		MenuKit.COL_INK if slot == 0 else MenuKit.COL_ACCENT, 0)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.custom_minimum_size = Vector2(0, 68)
	box.add_child(header)

	# 猴子形象
	var monkey_holder: Control = Control.new()
	monkey_holder.custom_minimum_size = Vector2(0, 150)
	monkey_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(monkey_holder)
	card.monkey = MenuKit.make_monkey_sprite(4.0, slot == 1)
	card.monkey.position = Vector2(250, 80)
	monkey_holder.add_child(card.monkey)

	# --- 未加入提示区 ---
	card.empty_box = VBoxContainer.new()
	(card.empty_box as VBoxContainer).add_theme_constant_override("separation", 14)
	box.add_child(card.empty_box)

	var join_label: Label = MenuKit.make_label(
		GameState.ui("按对应按键加入", "PRESS TO JOIN"), 28, Color(MenuKit.COL_INK, 0.75), 0
	)
	join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.empty_box.add_child(join_label)

	var key_names: Array[String] = ["W", "A", "S", "D"]
	if slot == 1:
		key_names = ["UP", "LEFT", "DOWN", "RIGHT"]
	card.empty_box.add_child(MenuKit.make_device_hint_row(
		key_names,
		["a"],
		GameState.ui("加入", "JOIN"),
		52.0,
		InputHub.menu_profile(),
	))

	# --- 已加入信息区 ---
	card.joined_box = VBoxContainer.new()
	(card.joined_box as VBoxContainer).add_theme_constant_override("separation", 14)
	box.add_child(card.joined_box)

	card.device_label = MenuKit.make_label("", 28, MenuKit.COL_INK, 0)
	card.device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.joined_box.add_child(card.device_label)

	var ready_row: HBoxContainer = HBoxContainer.new()
	ready_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ready_row.add_theme_constant_override("separation", 12)
	ready_row.add_child(MenuKit.make_icon("check_dark", 40.0))
	ready_row.add_child(MenuKit.make_label(
		GameState.ui("已准备", "READY!"), 36, MenuKit.COL_READY, 0
	))
	card.joined_box.add_child(ready_row)

	card.leave_hint = HBoxContainer.new()
	card.leave_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	card.leave_hint.add_theme_constant_override("separation", 10)
	card.joined_box.add_child(card.leave_hint)

	_cards.append(card)
	return panel

# ---------- 状态刷新 ----------

## 依据 InputHub 槽位状态刷新两张卡与 START 按钮
func _refresh() -> void:
	_slots_changed_ms = Time.get_ticks_msec()
	_refresh_back_hint()
	for slot: int in 2:
		var card: SlotCard = _cards[slot]
		var joined: bool = InputHub.is_joined(slot)
		card.empty_box.visible = not joined
		card.joined_box.visible = joined
		card.monkey.modulate = Color.WHITE if joined else Color(0.25, 0.22, 0.18, 0.45)
		if joined:
			MenuKit.set_label_text(card.device_label, InputHub.get_slot_label(slot))
			_fill_leave_hint(slot, card)

	var ready: bool = InputHub.both_ready()
	_start_btn.disabled = not ready
	_start_btn.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	if ready:
		MenuKit.set_pixel_outline_text(_start_hint, _start_prompt())
		_start_hint.modulate = Color(1, 1, 1, 1)
		_start_btn.grab_focus()
	else:
		MenuKit.set_pixel_outline_text(
			_start_hint, GameState.ui("等待玩家加入…", "WAITING FOR PLAYERS...")
		)
		_start_hint.modulate = Color(1, 1, 1, 0.7)

## 已有槽位优先按会话组合显示；尚未加入时按已连接设备显示。
func _refresh_back_hint() -> void:
	for child: Node in _back_hint_holder.get_children():
		child.queue_free()
	var profile: InputHub.SessionProfile = InputHub.session_profile()
	if profile == InputHub.SessionProfile.UNKNOWN:
		profile = InputHub.menu_profile()
	_back_hint_holder.add_child(MenuKit.make_device_hint_row(
		["ESC"],
		["b"],
		GameState.ui("返回", "BACK"),
		44.0,
		profile,
	))

## 填充"如何退出"提示（按设备不同展示不同按键）
func _fill_leave_hint(slot: int, card: SlotCard) -> void:
	for child: Node in card.leave_hint.get_children():
		child.queue_free()
	var kind: InputHub.SourceKind = InputHub.slot_kind(slot)
	if kind == InputHub.SourceKind.JOYPAD:
		card.leave_hint.add_child(MenuKit.make_pad_icon("b", 36.0))
	else:
		card.leave_hint.add_child(MenuKit.make_key_icon("X" if slot == 0 else "DEL", 36.0))
	card.leave_hint.add_child(MenuKit.make_label(
		GameState.ui("退出", "LEAVE"), 28, Color(MenuKit.COL_INK, 0.5), 0
	))

## 双方就绪后按实际输入组合生成开始提示。
func _start_prompt() -> String:
	match InputHub.session_profile():
		InputHub.SessionProfile.GAMEPAD_ONLY:
			return GameState.ui("按手柄 A 开始", "PRESS (A) TO START")
		InputHub.SessionProfile.MIXED:
			return GameState.ui("按 ENTER / 手柄 A 开始", "PRESS ENTER / (A) TO START")
		_:
			return GameState.ui("按 ENTER 开始", "PRESS ENTER TO START")

## 顶部通知（手柄插拔等）
func _show_toast(text: String) -> void:
	MenuKit.set_pixel_outline_text(_toast, text)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)

# ---------- 输入处理 ----------

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_W, KEY_A, KEY_S, KEY_D:
			# P1 键盘加入（槽位空且 WASD 未被占用才生效）
			if not InputHub.is_joined(0) \
				and InputHub.find_kind_slot(InputHub.SourceKind.KEYBOARD_WASD) < 0:
				InputHub.join_slot(0, InputHub.SourceKind.KEYBOARD_WASD)
				_cards[0].spring.punch(0.3)
				AudioHub.play_ui_ready()
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if not InputHub.is_joined(1) \
				and InputHub.find_kind_slot(InputHub.SourceKind.KEYBOARD_ARROWS) < 0:
				InputHub.join_slot(1, InputHub.SourceKind.KEYBOARD_ARROWS)
				_cards[1].spring.punch(0.3)
				AudioHub.play_ui_ready()
		KEY_X:
			if InputHub.slot_kind(0) == InputHub.SourceKind.KEYBOARD_WASD:
				InputHub.leave_slot(0)
				AudioHub.play_ui_error()
		KEY_DELETE, KEY_BACKSPACE:
			if InputHub.slot_kind(1) == InputHub.SourceKind.KEYBOARD_ARROWS:
				InputHub.leave_slot(1)
				AudioHub.play_ui_error()
		KEY_ESCAPE:
			InputHub.clear_slots()
			SceneDirector.go_to(GameState.pairing_back_scene())

## 直接接收 InputHub 翻译后的手柄动作，避免轮询与 UI 控件争抢同一次按键。
func _input(event: InputEvent) -> void:
	var action_event: InputEventAction = event as InputEventAction
	if action_event == null or not action_event.pressed:
		return
	if action_event.action == InputHub.UI_ACCEPT_ACTION:
		get_viewport().set_input_as_handled()
		_on_pad_accept(action_event.device)
	elif action_event.action == InputHub.UI_CANCEL_ACTION:
		get_viewport().set_input_as_handled()
		_on_pad_cancel(action_event.device)

## 手柄 A：未加入 → 认领空槽位；已加入且双方就绪 → 开始
func _on_pad_accept(joy_id: int) -> void:
	# InputEventAction.device 偶发丢失；回退到当前按下确认键的真实手柄。
	if joy_id < 0:
		for candidate: int in Input.get_connected_joypads():
			if InputHub.is_joy_accept_pressed(candidate):
				joy_id = candidate
				break
	if joy_id < 0:
		return
	if InputHub.find_joypad_slot(joy_id) < 0:
		var slot: int = InputHub.claim_joypad(joy_id)
		if slot >= 0:
			_cards[slot].spring.punch(0.3)
			HapticHub.confirm_join(joy_id)
			AudioHub.play_ui_ready()
		return
	# 防止加入瞬间的同一次按键立即触发开始
	if InputHub.both_ready() and Time.get_ticks_msec() - _slots_changed_ms > 500:
		_on_start()

## 手柄 B：已加入时先退出自己的槽位；未加入时返回实验录入。
func _on_pad_cancel(joy_id: int) -> void:
	var slot: int = InputHub.find_joypad_slot(joy_id)
	if slot >= 0:
		InputHub.leave_slot(slot)
		AudioHub.play_ui_error()
		return
	InputHub.clear_slots()
	SceneDirector.go_to(GameState.pairing_back_scene())

func _on_hotplug(device_id: int, connected: bool) -> void:
	if connected:
		AudioHub.play_ui_ready()
		_show_toast(GameState.ui(
			"手柄 %d 已连接 · 按 A 加入" % (device_id + 1),
			"GAMEPAD %d CONNECTED - PRESS (A) TO JOIN" % (device_id + 1),
		))
	else:
		AudioHub.play_ui_error()
		_show_toast(GameState.ui(
			"手柄 %d 已断开" % (device_id + 1),
			"GAMEPAD %d DISCONNECTED" % (device_id + 1),
		))

func _on_start() -> void:
	if not InputHub.both_ready():
		return
	# 所有组合都进入输入检查页：手柄做校准，键盘明确显示“无需校准”。
	SceneDirector.go_to("res://scenes/calibration_screen.tscn")
