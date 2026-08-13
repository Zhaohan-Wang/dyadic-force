extends SceneTree
## 断言：静摩擦门槛使单人无法稳定起步，双人约 65%～100% 同向可启动；
## 满推力加大后失配扭矩更强，但仍无特例物理。
## 用法：godot --headless --path . --script res://tools/ball_push_assert.gd

func _initialize() -> void:
	# 与 scenes/level.tscn / PixelBall 默认参数对齐
	var normal_accel: float = 150.0
	var tangent_accel: float = 145.0
	var static_friction: float = 145.0
	var kinetic_friction: float = 30.0
	var traction_floor: float = 0.35
	var radius: float = 44.0

	# 顶/底猴子水平满推：力几乎纯切向
	var solo_force_mag: float = tangent_accel
	var solo_torque: float = radius * solo_force_mag
	var solo_slip: float = clampf(absf(solo_torque) / (radius * solo_force_mag), 0.0, 1.0)
	var solo_traction: float = lerpf(traction_floor, 1.0, 1.0 - solo_slip)
	var solo_drive: float = solo_force_mag * solo_traction

	var duo_force_mag: float = 2.0 * tangent_accel
	var duo_slip: float = 0.0
	var duo_traction: float = lerpf(traction_floor, 1.0, 1.0 - duo_slip)
	var duo_drive: float = duo_force_mag * duo_traction
	var duo_70_drive: float = 0.70 * duo_drive
	var duo_65_drive: float = 0.65 * duo_drive

	# 反向：净平移约 0，扭矩叠加 → 打滑满
	var oppose_net: float = 0.0
	var oppose_torque: float = 2.0 * radius * tangent_accel
	var oppose_sum: float = 2.0 * tangent_accel
	var oppose_slip: float = clampf(absf(oppose_torque) / (radius * oppose_sum), 0.0, 1.0)

	assert(is_equal_approx(solo_slip, 1.0), "solo rim push must fully slip")
	assert(solo_drive < static_friction, "solo full push must not clear static friction")
	assert(duo_drive > static_friction + 80.0, "dual aligned push must clearly clear static friction")
	assert(duo_70_drive >= static_friction, "dual 70%% aligned must start")
	assert(duo_65_drive >= static_friction - 1.0, "dual ~65%% aligned should be near start threshold")
	assert(duo_drive > solo_drive * 3.0, "aligned duo translation must dominate solo")
	assert(is_equal_approx(oppose_slip, 1.0), "opposed inputs must fully slip")
	assert(oppose_net < 0.01, "opposed inputs must cancel translation")
	assert(oppose_torque > radius * 250.0, "full oppose must produce strong torque")
	assert(kinetic_friction < static_friction * 0.35, "kinetic friction must stay well below static")
	assert(normal_accel >= tangent_accel, "normal traction should be >= tangent")

	print(
		"ball_push_assert OK  solo=%.1f duo=%.1f duo70=%.1f static=%.1f torque=%.0f"
		% [solo_drive, duo_drive, duo_70_drive, static_friction, oppose_torque]
	)
	quit(0)
