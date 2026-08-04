extends Node
## 双玩家手柄震动。
##
## 保留：选手柄加入、校准完成、关卡内扣血、进传送门渐强震。
## 禁止：启动游戏、热插拔连接、点开始、移动中持续震动、按速度猜碰撞。
##
## Switch Pro（macOS）会吞“按键/摇杆仍按下时的同帧短脉冲”。
## 确认/校准能震，是因为先等松开再震；扣血也必须走同一套时序。

var _level_active: bool = false
var _damage_token: int = 0
var _teleport_token: int = 0
var _active_devices: Dictionary[int, bool] = {}

func _ready() -> void:
	InputHub.joy_hotplug.connect(_on_joy_hotplug)
	GameState.settings_changed.connect(_on_settings_changed)

func begin_level(_health: BallHealth = null) -> void:
	# 扣血改由 BallHealth / Level 直接调 pulse_damage，不再靠信号接线。
	end_level()
	_level_active = true
	_damage_token = 0
	_teleport_token = 0

func end_level() -> void:
	_damage_token += 1
	_teleport_token += 1
	_stop_all()
	_level_active = false

func preview_device(joy_id: int) -> void:
	_confirm_pulse(joy_id)

func preview_connected() -> void:
	if GameState.haptic_strength <= 0.001:
		_stop_all()
		return
	for joy_id: int in Input.get_connected_joypads():
		preview_device(joy_id)

## 按 A 加入槽位：等确认键松开后再震，避免 Switch Pro 吞同帧脉冲。
func confirm_join(joy_id: int) -> void:
	joy_id = _resolve_joy_id(joy_id)
	if joy_id < 0:
		return
	await _wait_accept_release(joy_id, 0.8)
	await get_tree().create_timer(0.05, true, false, true).timeout
	if not Input.get_connected_joypads().has(joy_id):
		return
	await _confirm_pulse(joy_id)

## 校准完成：回中后两段上扬确认。
func confirm_calibration(joy_id: int) -> void:
	joy_id = _resolve_joy_id(joy_id)
	if joy_id < 0:
		return
	await _wait_idle(joy_id, 1.2)
	await get_tree().create_timer(0.04, true, false, true).timeout
	if not Input.get_connected_joypads().has(joy_id):
		return
	Input.stop_joy_vibration(joy_id)
	_pulse(joy_id, 0.70, 1.0, 0.22)
	await get_tree().create_timer(0.26, true, false, true).timeout
	if Input.get_connected_joypads().has(joy_id):
		_pulse(joy_id, 0.85, 1.0, 0.30)

## 扣血震动：与确认同一时序（停 → 等帧 → 强脉冲）。半格小震，≥1 格大震。
func pulse_damage(amount: float) -> void:
	if not _level_active or amount <= 0.0:
		return
	if GameState.haptic_strength <= 0.001:
		return
	var devices: Array[int] = _devices_to_pulse()
	if devices.is_empty():
		return

	_damage_token += 1
	var token: int = _damage_token
	var large: bool = HapticProfile.is_large_hit(amount)

	for joy_id: int in devices:
		Input.stop_joy_vibration(joy_id)
	# 关键帧摇杆往往仍满推；给驱动两帧空隙，否则 Switch Pro 经常直接吞掉。
	await get_tree().process_frame
	await get_tree().process_frame
	if token != _damage_token or not _level_active:
		return

	# 小震也顶到接近确认震的马达阈值；Switch Pro 低于约 0.7 经常完全不振。
	var weak: float = 0.95 if large else 0.78
	var strong: float = 1.0 if large else 1.0
	var duration: float = 0.36 if large else 0.30
	_pulse_devices(devices, weak, strong, duration)
	# 撞墙时摇杆常仍满推，驱动可能吞掉第一下；若未真正起振则立刻补一枪。
	await get_tree().create_timer(0.05, true, false, true).timeout
	if token != _damage_token or not _level_active:
		return
	var needs_retry: bool = false
	for joy_id: int in devices:
		if (
			Input.get_connected_joypads().has(joy_id)
			and Input.get_joy_vibration_strength(joy_id).y < 0.20
		):
			needs_retry = true
			break
	if needs_retry:
		_pulse_devices(devices, weak, strong, duration)

## 进传送门：从弱到强的一段渐强震，时长与 TeleportFx 演出对齐。
## 不 await 调用方；内部自行推进，离开关卡时会被 end_level 打断。
func play_teleport_rumble(duration: float = 1.45) -> void:
	if not _level_active or duration <= 0.0:
		return
	if GameState.haptic_strength <= 0.001:
		return
	var devices: Array[int] = _devices_to_pulse()
	if devices.is_empty():
		return

	_damage_token += 1
	_teleport_token += 1
	var token: int = _teleport_token
	for joy_id: int in devices:
		Input.stop_joy_vibration(joy_id)

	var steps: int = 14
	var step_s: float = duration / float(steps)
	for i: int in steps:
		if token != _teleport_token or not _level_active:
			return
		# 二次缓入：前半段轻，后半段明显顶满。
		var t: float = float(i) / float(maxi(steps - 1, 1))
		var ease_t: float = t * t
		var weak: float = lerpf(0.42, 0.95, ease_t)
		var strong: float = lerpf(0.55, 1.0, ease_t)
		_pulse_devices(devices, weak, strong, step_s + 0.04)
		await get_tree().create_timer(step_s, true, false, true).timeout

	if token != _teleport_token or not _level_active:
		return
	# 收束一记满振，对应升空闪点
	_pulse_devices(devices, 1.0, 1.0, 0.28)
	await get_tree().create_timer(0.22, true, false, true).timeout
	if token == _teleport_token:
		_stop_all()

func _devices_to_pulse() -> Array[int]:
	var devices: Array[int] = []
	for slot: int in 2:
		if InputHub.slot_kind(slot) != InputHub.SourceKind.JOYPAD:
			continue
		var joy_id: int = InputHub.slot_joy_id(slot)
		if joy_id >= 0 and Input.get_connected_joypads().has(joy_id) and not devices.has(joy_id):
			devices.append(joy_id)
	# 槽位异常时仍震已连接手柄，避免“确认能震、关卡零反馈”。
	if devices.is_empty():
		for joy_id: int in Input.get_connected_joypads():
			devices.append(joy_id)
	return devices

func _pulse_devices(devices: Array[int], weak: float, strong: float, duration: float) -> void:
	for joy_id: int in devices:
		if Input.get_connected_joypads().has(joy_id):
			_pulse(joy_id, weak, strong, duration)

func _on_joy_hotplug(device_id: int, connected: bool) -> void:
	if not connected:
		Input.stop_joy_vibration(device_id)
		_active_devices.erase(device_id)

func _on_settings_changed() -> void:
	if GameState.haptic_strength <= 0.001:
		_stop_all()

func _confirm_pulse(joy_id: int) -> void:
	if joy_id < 0 or GameState.haptic_strength <= 0.001:
		return
	Input.stop_joy_vibration(joy_id)
	await get_tree().process_frame
	_pulse(joy_id, 0.78, 1.0, 0.28)

func _pulse(joy_id: int, weak: float, strong: float, duration: float) -> void:
	if joy_id < 0 or GameState.haptic_strength <= 0.001:
		return
	var master: float = clampf(GameState.haptic_strength, 0.0, 1.0)
	Input.start_joy_vibration(
		joy_id,
		clampf(weak * master, 0.0, 1.0),
		clampf(strong * master, 0.0, 1.0),
		duration,
	)
	_active_devices[joy_id] = true

func _resolve_joy_id(joy_id: int) -> int:
	if joy_id >= 0 and Input.get_connected_joypads().has(joy_id):
		return joy_id
	for candidate: int in Input.get_connected_joypads():
		if InputHub.is_joy_accept_pressed(candidate):
			return candidate
	var connected: PackedInt32Array = Input.get_connected_joypads()
	if connected.size() == 1:
		return connected[0]
	return -1

func _wait_accept_release(joy_id: int, timeout_s: float) -> void:
	var left: float = timeout_s
	while left > 0.0 and InputHub.is_joy_accept_pressed(joy_id):
		await get_tree().process_frame
		left -= get_process_delta_time()

func _wait_idle(joy_id: int, timeout_s: float) -> void:
	var left: float = timeout_s
	while left > 0.0:
		var stick: Vector2 = Vector2(
			Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y),
		)
		if (
			stick.length() < 0.20
			and not InputHub.is_joy_accept_pressed(joy_id)
			and not InputHub.is_joy_cancel_pressed(joy_id)
		):
			return
		await get_tree().process_frame
		left -= get_process_delta_time()

func _stop_all() -> void:
	for device_id: int in _active_devices.keys():
		Input.stop_joy_vibration(device_id)
	_active_devices.clear()
	for device_id: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device_id)
