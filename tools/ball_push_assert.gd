extends SceneTree
## 断言：满推时引擎加速度必须明显高于滚动摩擦，否则球会表现为“死沉推不动”。

func _initialize() -> void:
	var push_force: float = 150.0
	var friction_decel: float = 42.0
	var f_max: float = ForceMapper.DEFAULT_FMAX
	var sample: ForceMapper.Sample = ForceMapper.map_digital(Vector2.RIGHT, 1.0, f_max)
	var accel_one: float = sample.move.length() * push_force
	var accel_two: float = accel_one * 2.0
	# 错误公式曾再除一次 Fmax，满推只剩约 18.75，低于摩擦 55。
	var broken_accel: float = sample.move.length() * (push_force / f_max)
	assert(is_equal_approx(sample.move.length(), 1.0), "full digital move must be 1")
	assert(accel_one > friction_decel + 40.0, "single full push must beat rolling friction")
	assert(accel_two > friction_decel + 100.0, "dual full push must clearly move the ball")
	assert(broken_accel < friction_decel, "sanity: the old double-divide formula remains too weak")
	print("ball_push_assert OK  one=%.1f two=%.1f friction=%.1f" % [
		accel_one, accel_two, friction_decel,
	])
	quit(0)
