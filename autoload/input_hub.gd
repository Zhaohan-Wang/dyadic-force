extends Node
## 输入路由中枢：把玩家槽位（P1/P2）映射到具体设备来源，
## 并按实验协议完成「原始摇杆 → 中心校准 → 径向死区 → γ 曲线 → 虚拟作用力」。
##
## 交互原则：绝不默认绑定。两个槽位初始都是空的，
## 玩家必须在配对界面主动按键加入（键盘 WASD/方向键、手柄 A），
## 也可以随时退出；手柄拔出时槽位自动清空并通知 UI。

## UI 动作名统一由这里分发，避免场景直接依赖 Xbox 的 AB 位置。
const UI_ACCEPT_ACTION: StringName = &"ui_accept"
const UI_CANCEL_ACTION: StringName = &"ui_cancel"
## SDL/Godot GUID 中 Nintendo 厂商 ID（0x057e）的小端表示。
const NINTENDO_GUID_VENDOR: String = "7e05"
## 无法从 GUID 判断时使用的 Nintendo 设备名特征。
const NINTENDO_NAME_MARKERS: PackedStringArray = [
	"nintendo",
	"switch",
	"joy-con",
	"joycon",
]

enum SourceKind {
	NONE,             ## 空槽位（未加入）
	KEYBOARD_WASD,    ## 键盘 WASD
	KEYBOARD_ARROWS,  ## 键盘方向键
	JOYPAD,           ## 手柄
}

## 当前双人会话的设备组合，用于动态生成操作提示。
enum SessionProfile {
	UNKNOWN,
	KEYBOARD_ONLY,
	GAMEPAD_ONLY,
	MIXED,
}

## 单个槽位的输入来源描述
class InputSource:
	var kind: SourceKind = SourceKind.NONE
	var joy_id: int = -1  # JOYPAD 时有效

	func _init(p_kind: SourceKind = SourceKind.NONE, p_joy_id: int = -1) -> void:
		kind = p_kind
		joy_id = p_joy_id

## 单设备会话校准数据（拔插即失效）
class JoyCalibration:
	var center_offset: Vector2 = Vector2.ZERO
	var max_radial: float = 0.0
	var drift_max: float = 0.0
	var passed: bool = false

## 槽位占用变更（配对界面订阅刷新）
signal slots_changed
## 手柄热插拔（connected=true 插入，false 拔出）
signal joy_hotplug(device_id: int, connected: bool)

## 两名玩家的输入来源（初始都为空）
var _slots: Array[InputSource] = []
## 输入是否被冻结（结算 / 重生过渡时）
var input_frozen: bool = false
## 每个槽位的输入增益（0～1）；第 3 关“输入缩减”时段由关卡驱动，平时恒为 1.0
var slot_gains: Array[float] = [1.0, 1.0]
## joy_id → JoyCalibration；仅当前连接会话有效
var _joy_calibrations: Dictionary[int, JoyCalibration] = {}
## 力映射参数（可由实验配置覆盖）
var deadzone: float = ForceMapper.DEFAULT_DEADZONE
var gamma: float = ForceMapper.DEFAULT_GAMMA
var f_max: float = ForceMapper.DEFAULT_FMAX

func _ready() -> void:
	_slots = [InputSource.new(), InputSource.new()]
	_remove_default_face_button_actions()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

## 根据已加入的两个槽位判断纯键盘、纯手柄或混合输入。
func session_profile() -> SessionProfile:
	var has_keyboard: bool = false
	var has_gamepad: bool = false
	for source: InputSource in _slots:
		match source.kind:
			SourceKind.KEYBOARD_WASD, SourceKind.KEYBOARD_ARROWS:
				has_keyboard = true
			SourceKind.JOYPAD:
				has_gamepad = true
	if has_keyboard and has_gamepad:
		return SessionProfile.MIXED
	if has_gamepad:
		return SessionProfile.GAMEPAD_ONLY
	if has_keyboard:
		return SessionProfile.KEYBOARD_ONLY
	return SessionProfile.UNKNOWN

## 配对前没有槽位信息：无手柄时只提示键盘，有手柄时提示两种输入。
func menu_profile() -> SessionProfile:
	var profile: SessionProfile = session_profile()
	if profile != SessionProfile.UNKNOWN:
		return profile
	if Input.get_connected_joypads().is_empty():
		return SessionProfile.KEYBOARD_ONLY
	return SessionProfile.MIXED

## 把手柄面键翻译成统一 UI 动作：
## Xbox 使用底部 A / 右侧 B，Nintendo 使用右侧 A / 底部 B。
func _input(event: InputEvent) -> void:
	var button_event: InputEventJoypadButton = event as InputEventJoypadButton
	if button_event == null:
		return
	var action: StringName = joy_ui_action(button_event.device, button_event.button_index)
	if action == &"":
		return
	var action_event: InputEventAction = InputEventAction.new()
	action_event.action = action
	action_event.pressed = button_event.pressed
	# JoypadButton.pressure 在 Godot 中不会由驱动赋值，数字面键按下必须显式使用 1.0。
	action_event.strength = 1.0 if button_event.pressed else 0.0
	action_event.device = button_event.device
	Input.parse_input_event(action_event)

## 返回指定面键对应的统一 UI 动作；非确认/取消键返回空 StringName。
func joy_ui_action(joy_id: int, button_index: int) -> StringName:
	var accept_button: int = JOY_BUTTON_B if is_nintendo_joypad(joy_id) else JOY_BUTTON_A
	var cancel_button: int = JOY_BUTTON_A if is_nintendo_joypad(joy_id) else JOY_BUTTON_B
	if button_index == accept_button:
		return UI_ACCEPT_ACTION
	if button_index == cancel_button:
		return UI_CANCEL_ACTION
	return &""

## 当前手柄的确认键是否按下（Xbox A / Nintendo A）。
func is_joy_accept_pressed(joy_id: int) -> bool:
	var button: int = JOY_BUTTON_B if is_nintendo_joypad(joy_id) else JOY_BUTTON_A
	return Input.is_joy_button_pressed(joy_id, button)

## 当前手柄的取消键是否按下（Xbox B / Nintendo B）。
func is_joy_cancel_pressed(joy_id: int) -> bool:
	var button: int = JOY_BUTTON_A if is_nintendo_joypad(joy_id) else JOY_BUTTON_B
	return Input.is_joy_button_pressed(joy_id, button)

## 根据设备 GUID 与名称识别 Nintendo 手柄，兼容 Switch Pro 与 Joy-Con。
func is_nintendo_joypad(joy_id: int) -> bool:
	var guid: String = Input.get_joy_guid(joy_id).to_lower()
	if guid.length() >= 12 and guid.substr(8, 4) == NINTENDO_GUID_VENDOR:
		return true
	var joy_name: String = Input.get_joy_name(joy_id).to_lower()
	if joy_name == "pro controller":
		return true
	for marker: String in NINTENDO_NAME_MARKERS:
		if joy_name.contains(marker):
			return true
	return false

## Godot 内置 ui_accept/ui_cancel 采用 Xbox 面键位置；移除后由 _input 按设备翻译，
## 同时保留键盘、鼠标和方向轴等原有 UI 映射。
func _remove_default_face_button_actions() -> void:
	for action: StringName in [UI_ACCEPT_ACTION, UI_CANCEL_ACTION]:
		for mapped_event: InputEvent in InputMap.action_get_events(action):
			var mapped_button: InputEventJoypadButton = mapped_event as InputEventJoypadButton
			if mapped_button == null:
				continue
			if mapped_button.button_index in [JOY_BUTTON_A, JOY_BUTTON_B]:
				InputMap.action_erase_event(action, mapped_event)

# ---------- 游戏内读取 ----------

## 读取某槽位的完整力采样（实验日志与物理共用同一帧结果）。
func get_force_sample(slot: int) -> ForceMapper.Sample:
	if input_frozen or slot < 0 or slot >= _slots.size():
		return ForceMapper.Sample.new()
	var src: InputSource = _slots[slot]
	var gain: float = clampf(slot_gains[slot], 0.0, 1.0)
	match src.kind:
		SourceKind.KEYBOARD_WASD:
			var key_dir: Vector2 = Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
			return ForceMapper.map_digital(key_dir, gain, f_max)
		SourceKind.KEYBOARD_ARROWS:
			var arrow_dir: Vector2 = Input.get_vector("p2_left", "p2_right", "p2_up", "p2_down")
			return ForceMapper.map_digital(arrow_dir, gain, f_max)
		SourceKind.JOYPAD:
			return _sample_joypad(src.joy_id, gain)
	return ForceMapper.Sample.new()

## 兼容旧调用：返回 force/Fmax（方向连续、幅值 = m2·gain）。
func get_move_vector(slot: int) -> Vector2:
	return get_force_sample(slot).move

## 重置全部槽位增益为 1（关卡进出时调用，防止残留到其他场景）
func reset_gains() -> void:
	slot_gains = [1.0, 1.0]

## 读取手柄左摇杆原始轴（未校准、未映射）。
func read_raw_stick(joy_id: int) -> Vector2:
	if joy_id < 0 or not Input.get_connected_joypads().has(joy_id):
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y)
	)

## 对手柄做完整力采样：摇杆优先，否则十字键走数字满幅。
func _sample_joypad(joy_id: int, gain: float) -> ForceMapper.Sample:
	if joy_id < 0 or not Input.get_connected_joypads().has(joy_id):
		return ForceMapper.Sample.new()
	var raw: Vector2 = read_raw_stick(joy_id)
	var center: Vector2 = get_center_offset(joy_id)
	var stick_sample: ForceMapper.Sample = ForceMapper.map_stick(
		raw, center, gain, deadzone, gamma, f_max
	)
	if stick_sample.force != Vector2.ZERO:
		return stick_sample
	# 摇杆在死区内时回退十字键（数字满幅）
	var dpad: Vector2 = Vector2.ZERO
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_LEFT):
		dpad.x -= 1.0
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_RIGHT):
		dpad.x += 1.0
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_UP):
		dpad.y -= 1.0
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_DOWN):
		dpad.y += 1.0
	if dpad == Vector2.ZERO:
		return stick_sample
	var digital: ForceMapper.Sample = ForceMapper.map_digital(dpad, gain, f_max)
	# 保留原始轴读数，便于日志对照
	digital.raw = raw
	digital.calibrated = raw - center
	digital.m = digital.calibrated.length()
	return digital

# ---------- 校准 ----------

## 查询设备中心偏移；未校准则为零。
func get_center_offset(joy_id: int) -> Vector2:
	var cal: JoyCalibration = _joy_calibrations.get(joy_id) as JoyCalibration
	if cal == null:
		return Vector2.ZERO
	return cal.center_offset

## 某手柄是否已通过本会话校准。
func is_joy_calibrated(joy_id: int) -> bool:
	var cal: JoyCalibration = _joy_calibrations.get(joy_id) as JoyCalibration
	return cal != null and cal.passed

## 写入静置阶段结果（中心均值与最大漂移）。
func set_joy_rest_calibration(joy_id: int, center: Vector2, drift_max: float) -> void:
	var cal: JoyCalibration = _joy_calibrations.get(joy_id) as JoyCalibration
	if cal == null:
		cal = JoyCalibration.new()
		_joy_calibrations[joy_id] = cal
	cal.center_offset = center
	cal.drift_max = drift_max
	cal.passed = false

## 标记绕圈校准通过，并记录测得的最大径向值。
func mark_joy_circle_passed(joy_id: int, max_radial: float) -> void:
	var cal: JoyCalibration = _joy_calibrations.get(joy_id) as JoyCalibration
	if cal == null:
		cal = JoyCalibration.new()
		_joy_calibrations[joy_id] = cal
	cal.max_radial = max_radial
	cal.passed = true

## 清除某设备校准（拔出或失败重试）。
func clear_joy_calibration(joy_id: int) -> void:
	_joy_calibrations.erase(joy_id)

## 已加入的手柄是否全部完成校准；纯键盘局恒为 true。
func all_joined_joypads_calibrated() -> bool:
	for i: int in _slots.size():
		var src: InputSource = _slots[i]
		if src.kind == SourceKind.JOYPAD and not is_joy_calibrated(src.joy_id):
			return false
	return true

## 是否有手柄槽位加入（决定是否需要进入校准页）。
func has_joypad_joined() -> bool:
	for i: int in _slots.size():
		if _slots[i].kind == SourceKind.JOYPAD:
			return true
	return false

## 收集已加入手柄的 joy_id 列表。
func joined_joy_ids() -> Array[int]:
	var ids: Array[int] = []
	for i: int in _slots.size():
		var src: InputSource = _slots[i]
		if src.kind == SourceKind.JOYPAD and src.joy_id >= 0:
			ids.append(src.joy_id)
	return ids

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

## 查询槽位手柄 ID（非手柄返回 -1）
func slot_joy_id(slot: int) -> int:
	if slot < 0 or slot >= _slots.size():
		return -1
	return _slots[slot].joy_id

## 查询槽位来源描述（供 UI 显示，英文像素字）
func get_slot_label(slot: int) -> String:
	if slot < 0 or slot >= _slots.size():
		return ""
	var src: InputSource = _slots[slot]
	match src.kind:
		SourceKind.KEYBOARD_WASD:
			return GameState.ui("键盘", "KEYBOARD")
		SourceKind.KEYBOARD_ARROWS:
			return GameState.ui("键盘", "KEYBOARD")
		SourceKind.JOYPAD:
			return GameState.ui(
				"手柄 %d" % (src.joy_id + 1),
				"GAMEPAD %d" % (src.joy_id + 1),
			)
	return ""

## 两名玩家是否都已加入
func both_ready() -> bool:
	return is_joined(0) and is_joined(1)

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if not connected:
		# 拔出手柄 → 槽位清空，校准一并失效
		clear_joy_calibration(device_id)
		var slot: int = find_joypad_slot(device_id)
		if slot >= 0:
			_slots[slot] = InputSource.new()
			slots_changed.emit()
	joy_hotplug.emit(device_id, connected)
