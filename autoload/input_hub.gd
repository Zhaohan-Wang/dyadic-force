extends Node
## 输入路由中枢：把玩家槽位（P1/P2）映射到具体设备来源。
##
## 交互原则：绝不默认绑定。两个槽位初始都是空的，
## 玩家必须在配对界面主动按键加入（键盘 WASD/方向键、手柄 A），
## 也可以随时退出；手柄拔出时槽位自动清空并通知 UI。

enum SourceKind {
	NONE,             ## 空槽位（未加入）
	KEYBOARD_WASD,    ## 键盘 WASD
	KEYBOARD_ARROWS,  ## 键盘方向键
	JOYPAD,           ## 手柄
}

## 单个槽位的输入来源描述
class InputSource:
	var kind: SourceKind = SourceKind.NONE
	var joy_id: int = -1  # JOYPAD 时有效

	func _init(p_kind: SourceKind = SourceKind.NONE, p_joy_id: int = -1) -> void:
		kind = p_kind
		joy_id = p_joy_id

## 槽位占用变更（配对界面订阅刷新）
signal slots_changed
## 手柄热插拔（connected=true 插入，false 拔出）
signal joy_hotplug(device_id: int, connected: bool)

## 两名玩家的输入来源（初始都为空）
var _slots: Array[InputSource] = []
## 输入是否被冻结（结算 / 重生过渡时）
var input_frozen: bool = false

func _ready() -> void:
	_slots = [InputSource.new(), InputSource.new()]
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

# ---------- 游戏内读取 ----------

## 读取某槽位的移动向量（归一化，死区已处理）；空槽位恒为零
func get_move_vector(slot: int) -> Vector2:
	if input_frozen or slot < 0 or slot >= _slots.size():
		return Vector2.ZERO
	var src: InputSource = _slots[slot]
	match src.kind:
		SourceKind.KEYBOARD_WASD:
			return Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
		SourceKind.KEYBOARD_ARROWS:
			return Input.get_vector("p2_left", "p2_right", "p2_up", "p2_down")
		SourceKind.JOYPAD:
			return _read_joypad(src.joy_id)
	return Vector2.ZERO

## 读取手柄左摇杆 / 十字键，合成一个方向向量
func _read_joypad(joy_id: int) -> Vector2:
	if joy_id < 0 or not Input.get_connected_joypads().has(joy_id):
		return Vector2.ZERO
	var stick: Vector2 = Vector2(
		Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y)
	)
	if stick.length() < 0.25:
		stick = Vector2.ZERO
	var dpad: Vector2 = Vector2.ZERO
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_LEFT):
		dpad.x -= 1.0
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_RIGHT):
		dpad.x += 1.0
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_UP):
		dpad.y -= 1.0
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_DOWN):
		dpad.y += 1.0
	var merged: Vector2 = stick if stick != Vector2.ZERO else dpad
	if merged.length_squared() > 1.0:
		merged = merged.normalized()
	return merged

# ---------- 加入 / 退出 ----------

## 玩家主动把某槽位绑定到指定来源（配对界面调用）
func join_slot(slot: int, kind: SourceKind, joy_id: int = -1) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	_slots[slot] = InputSource.new(kind, joy_id)
	slots_changed.emit()

## 玩家主动退出槽位
func leave_slot(slot: int) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	_slots[slot] = InputSource.new()
	slots_changed.emit()

## 手柄认领第一个空槽位；已占用则返回原槽位，无空位返回 -1
func claim_joypad(joy_id: int) -> int:
	var existing: int = find_joypad_slot(joy_id)
	if existing >= 0:
		return existing
	for i: int in _slots.size():
		if _slots[i].kind == SourceKind.NONE:
			_slots[i] = InputSource.new(SourceKind.JOYPAD, joy_id)
			slots_changed.emit()
			return i
	return -1

## 查询某手柄占用的槽位（未占用返回 -1）
func find_joypad_slot(joy_id: int) -> int:
	for i: int in _slots.size():
		if _slots[i].kind == SourceKind.JOYPAD and _slots[i].joy_id == joy_id:
			return i
	return -1

## 查询某来源类型占用的槽位（未占用返回 -1）
func find_kind_slot(kind: SourceKind) -> int:
	for i: int in _slots.size():
		if _slots[i].kind == kind:
			return i
	return -1

## 清空全部槽位（回到配对界面时调用）
func clear_slots() -> void:
	_slots = [InputSource.new(), InputSource.new()]
	slots_changed.emit()

## 开发用兜底：直接跑关卡场景时补上默认键盘（正常流程不会走到这里）
func debug_assign_defaults() -> void:
	if both_ready():
		return
	_slots = [
		InputSource.new(SourceKind.KEYBOARD_WASD),
		InputSource.new(SourceKind.KEYBOARD_ARROWS),
	]
	slots_changed.emit()

# ---------- 查询 ----------

## 某槽位是否已有玩家加入
func is_joined(slot: int) -> bool:
	return slot >= 0 and slot < _slots.size() and _slots[slot].kind != SourceKind.NONE

## 查询槽位来源类型
func slot_kind(slot: int) -> SourceKind:
	if slot < 0 or slot >= _slots.size():
		return SourceKind.NONE
	return _slots[slot].kind

## 查询槽位来源描述（供 UI 显示，英文像素字）
func get_slot_label(slot: int) -> String:
	if slot < 0 or slot >= _slots.size():
		return ""
	var src: InputSource = _slots[slot]
	match src.kind:
		SourceKind.KEYBOARD_WASD:
			return "KEYBOARD"
		SourceKind.KEYBOARD_ARROWS:
			return "KEYBOARD"
		SourceKind.JOYPAD:
			return "GAMEPAD %d" % (src.joy_id + 1)
	return ""

## 两名玩家是否都已加入
func both_ready() -> bool:
	return is_joined(0) and is_joined(1)

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if not connected:
		# 拔出手柄 → 槽位清空，绝不悄悄回退到键盘
		var slot: int = find_joypad_slot(device_id)
		if slot >= 0:
			_slots[slot] = InputSource.new()
			slots_changed.emit()
	joy_hotplug.emit(device_id, connected)
