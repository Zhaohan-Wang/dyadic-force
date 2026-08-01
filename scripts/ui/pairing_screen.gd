extends Control
## 玩家配对界面：两个槽位默认为空，必须由玩家主动按键加入。
##
## 交互规则：
## - P1 按 WASD 任意键加入；P2 按方向键任意键加入
## - 手柄按 A 认领第一个空槽位
## - 退出：P1 键盘按 X、P2 键盘按 DEL、手柄按 B
## - 双方都加入后 START 才可用（Enter / 手柄 A / 点击）
## - ESC 返回标题并清空槽位；手柄拔出时对应槽位自动腾空

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
var _start_hint: Label
var _toast: Label
var _toast_tween: Tween = null
## 手柄按键边沿检测缓存 joy_id -> {a: bool, b: bool}
var _prev_pad: Dictionary = {}
## 最近一次槽位变化时间（防止加入的 A 键立刻触发开始）
var _slots_changed_ms: int = 0

func _ready() -> void:
	_build()
	InputHub.slots_changed.connect(_refresh)
	InputHub.joy_hotplug.connect(_on_hotplug)
	_refresh()

func _build() -> void:
	add_child(MenuKit.make_grass_bg())

	var title: Label = MenuKit.make_label("PAIR UP", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 64)
	title.size = Vector2(800, 72)
	add_child(title)
	UiSpring.attach(title, 0.5, 0.3).pop_in(0.02)

	var sub: Label = MenuKit.make_label("BOTH PLAYERS MUST JOIN TO START", 28, Color(1.0, 0.93, 0.78, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	_start_btn = MenuKit.make_big_button("START", 28, Vector2(440, 108))
	_start_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_btn.position = Vector2(-220, -232)
	_start_btn.pressed.connect(_on_start)
	add_child(_start_btn)
	UiSpring.attach(_start_btn, 0.45, 0.3).pop_in(0.3)

	_start_hint = MenuKit.make_label("WAITING FOR PLAYERS...", 28, Color(1, 1, 1, 0.7))
	_start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_hint.position = Vector2(-400, -108)
	_start_hint.size = Vector2(800, 40)
	add_child(_start_hint)

	# ---- 返回提示（左上角） ----
	var back_row: HBoxContainer = HBoxContainer.new()
	back_row.position = Vector2(40, 36)
	back_row.add_theme_constant_override("separation", 12)
	add_child(back_row)
	back_row.add_child(MenuKit.make_key_icon("ESC", 44.0))
	back_row.add_child(MenuKit.make_label("BACK", 28, Color(1, 1, 1, 0.75)))

	# ---- 顶部通知条 ----
	_toast = MenuKit.make_label("", 28, MenuKit.COL_CREAM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	# 玩家编号
	var header: Label = MenuKit.make_label(
		"P%d" % (slot + 1), 42,
		MenuKit.COL_INK if slot == 0 else MenuKit.COL_ACCENT, 0)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	var join_label: Label = MenuKit.make_label("PRESS TO JOIN", 28, Color(MenuKit.COL_INK, 0.75), 0)
	join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.empty_box.add_child(join_label)

	var keys_row: HBoxContainer = HBoxContainer.new()
	keys_row.alignment = BoxContainer.ALIGNMENT_CENTER
	keys_row.add_theme_constant_override("separation", 10)
	var key_names: Array[String] = ["W", "A", "S", "D"]
	if slot == 1:
		key_names = ["UP", "LEFT", "DOWN", "RIGHT"]
	for key: String in key_names:
		keys_row.add_child(MenuKit.make_key_icon(key, 56.0))
	card.empty_box.add_child(keys_row)

	var or_label: Label = MenuKit.make_label("- OR -", 28, Color(MenuKit.COL_INK, 0.5), 0)
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.empty_box.add_child(or_label)

	var pad_row: HBoxContainer = HBoxContainer.new()
	pad_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pad_row.add_theme_constant_override("separation", 12)
	pad_row.add_child(MenuKit.make_pad_icon("a", 56.0))
	pad_row.add_child(MenuKit.make_label("ON GAMEPAD", 28, Color(MenuKit.COL_INK, 0.75), 0))
	card.empty_box.add_child(pad_row)

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
	ready_row.add_child(MenuKit.make_label("READY!", 36, MenuKit.COL_READY, 0))
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
	for slot: int in 2:
		var card: SlotCard = _cards[slot]
		var joined: bool = InputHub.is_joined(slot)
		card.empty_box.visible = not joined
		card.joined_box.visible = joined
		card.monkey.modulate = Color.WHITE if joined else Color(0.25, 0.22, 0.18, 0.45)
		if joined:
			card.device_label.text = InputHub.get_slot_label(slot)
			_fill_leave_hint(slot, card)

	var ready: bool = InputHub.both_ready()
	_start_btn.disabled = not ready
	_start_btn.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	if ready:
		_start_hint.text = "PRESS ENTER OR (A) TO START"
		_start_hint.modulate = Color(1, 1, 1, 1)
		_start_btn.grab_focus()
	else:
		_start_hint.text = "WAITING FOR PLAYERS..."
		_start_hint.modulate = Color(1, 1, 1, 0.7)

## 填充"如何退出"提示（按设备不同展示不同按键）
func _fill_leave_hint(slot: int, card: SlotCard) -> void:
	for child: Node in card.leave_hint.get_children():
		child.queue_free()
	var kind: InputHub.SourceKind = InputHub.slot_kind(slot)
	if kind == InputHub.SourceKind.JOYPAD:
		card.leave_hint.add_child(MenuKit.make_pad_icon("b", 36.0))
	else:
		card.leave_hint.add_child(MenuKit.make_key_icon("X" if slot == 0 else "DEL", 36.0))
	card.leave_hint.add_child(MenuKit.make_label("LEAVE", 28, Color(MenuKit.COL_INK, 0.5), 0))

## 顶部通知（手柄插拔等）
func _show_toast(text: String) -> void:
	_toast.text = text
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
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if not InputHub.is_joined(1) \
				and InputHub.find_kind_slot(InputHub.SourceKind.KEYBOARD_ARROWS) < 0:
				InputHub.join_slot(1, InputHub.SourceKind.KEYBOARD_ARROWS)
				_cards[1].spring.punch(0.3)
		KEY_X:
			if InputHub.slot_kind(0) == InputHub.SourceKind.KEYBOARD_WASD:
				InputHub.leave_slot(0)
		KEY_DELETE, KEY_BACKSPACE:
			if InputHub.slot_kind(1) == InputHub.SourceKind.KEYBOARD_ARROWS:
				InputHub.leave_slot(1)
		KEY_ESCAPE:
			InputHub.clear_slots()
			SceneDirector.go_to("res://scenes/title_screen.tscn")

func _process(_delta: float) -> void:
	# 手柄 A/B 边沿检测：A 加入（或双就绪后开始），B 退出
	for joy_id: int in Input.get_connected_joypads():
		var a_now: bool = Input.is_joy_button_pressed(joy_id, JOY_BUTTON_A)
		var b_now: bool = Input.is_joy_button_pressed(joy_id, JOY_BUTTON_B)
		var prev: Dictionary = _prev_pad.get(joy_id, {"a": false, "b": false}) as Dictionary
		if a_now and not bool(prev["a"]):
			_on_pad_accept(joy_id)
		if b_now and not bool(prev["b"]):
			var slot: int = InputHub.find_joypad_slot(joy_id)
			if slot >= 0:
				InputHub.leave_slot(slot)
		_prev_pad[joy_id] = {"a": a_now, "b": b_now}

## 手柄 A：未加入 → 认领空槽位；已加入且双方就绪 → 开始
func _on_pad_accept(joy_id: int) -> void:
	if InputHub.find_joypad_slot(joy_id) < 0:
		var slot: int = InputHub.claim_joypad(joy_id)
		if slot >= 0:
			_cards[slot].spring.punch(0.3)
		return
	# 防止加入瞬间的同一次按键立即触发开始
	if InputHub.both_ready() and Time.get_ticks_msec() - _slots_changed_ms > 500:
		_on_start()

func _on_hotplug(device_id: int, connected: bool) -> void:
	if connected:
		_show_toast("GAMEPAD %d CONNECTED - PRESS (A) TO JOIN" % (device_id + 1))
	else:
		_show_toast("GAMEPAD %d DISCONNECTED" % (device_id + 1))

func _on_start() -> void:
	if InputHub.both_ready():
		SceneDirector.go_to("res://scenes/level_select.tscn")
