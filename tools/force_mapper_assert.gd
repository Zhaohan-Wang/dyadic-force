extends SceneTree
## Headless 力映射断言：验证死区边界、满幅、γ 中点、方向保持、径向一致性、增益顺序。
## 用法：godot --headless --path . --script res://tools/force_mapper_assert.gd

var _failed: int = 0
var _passed: int = 0

func _initialize() -> void:
	_run_all()
	print("FORCE_MAPPER_ASSERT passed=%d failed=%d" % [_passed, _failed])
	quit(_failed)

func _run_all() -> void:
	_assert_deadzone()
	_assert_full_push()
	_assert_gamma_midpoint()
	_assert_direction_preserved()
	_assert_radial_isotropy()
	_assert_gain_order()
	_assert_digital_full()

func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  OK  ", name)
	else:
		_failed += 1
		print("  FAIL ", name, " ", detail)

func _assert_deadzone() -> void:
	var below: ForceMapper.Sample = ForceMapper.map_stick(Vector2(0.11, 0.0))
	_check("deadzone below", below.force == Vector2.ZERO and below.m2 == 0.0)
	var at: ForceMapper.Sample = ForceMapper.map_stick(Vector2(0.12, 0.0))
	_check("deadzone at boundary", at.force == Vector2.ZERO)
	var above: ForceMapper.Sample = ForceMapper.map_stick(Vector2(0.121, 0.0))
	_check("deadzone above", above.m2 > 0.0 and above.force.x > 0.0)

func _assert_full_push() -> void:
	var s: ForceMapper.Sample = ForceMapper.map_stick(Vector2(1.0, 0.0))
	_check("full m1", _approx(s.m1, 1.0))
	_check("full m2", _approx(s.m2, 1.0))
	_check("full |F|", _approx(s.force.length(), ForceMapper.DEFAULT_FMAX))

func _assert_gamma_midpoint() -> void:
	# m = 0.5 → m1 = (0.5-0.12)/(0.88) ≈ 0.431818 → m2 = m1^1.6
	var m: float = 0.5
	var m1: float = (m - 0.12) / 0.88
	var expected_m2: float = pow(m1, 1.6)
	var s: ForceMapper.Sample = ForceMapper.map_stick(Vector2(m, 0.0))
	_check("gamma m1", _approx(s.m1, m1, 0.0005), "got %.6f want %.6f" % [s.m1, m1])
	_check("gamma m2", _approx(s.m2, expected_m2, 0.001), "got %.6f want %.6f" % [s.m2, expected_m2])
	_check("gamma |F|", _approx(s.force.length(), ForceMapper.DEFAULT_FMAX * expected_m2, 0.01))

func _assert_direction_preserved() -> void:
	var raw: Vector2 = Vector2(0.6, -0.35)
	var s: ForceMapper.Sample = ForceMapper.map_stick(raw)
	var want_angle: float = raw.angle()
	var got_angle: float = s.force.angle()
	_check("direction angle", _approx(want_angle, got_angle, 0.001))

func _assert_radial_isotropy() -> void:
	# 同一径向 m、不同角度 → |F| 应一致
	var m: float = 0.7
	var a: ForceMapper.Sample = ForceMapper.map_stick(Vector2(m, 0.0))
	var b: ForceMapper.Sample = ForceMapper.map_stick(Vector2(m, 0.0).rotated(PI * 0.25))
	var c: ForceMapper.Sample = ForceMapper.map_stick(Vector2(0.0, -m))
	_check("isotropy a/b", _approx(a.force.length(), b.force.length(), 0.001))
	_check("isotropy a/c", _approx(a.force.length(), c.force.length(), 0.001))

func _assert_gain_order() -> void:
	var full: ForceMapper.Sample = ForceMapper.map_stick(Vector2(0.8, 0.0), Vector2.ZERO, 1.0)
	var half: ForceMapper.Sample = ForceMapper.map_stick(Vector2(0.8, 0.0), Vector2.ZERO, 0.65)
	_check("gain scales force", _approx(half.force.length(), full.force.length() * 0.65, 0.01))
	_check("gain scales move", _approx(half.move.length(), full.move.length() * 0.65, 0.01))

func _assert_digital_full() -> void:
	var s: ForceMapper.Sample = ForceMapper.map_digital(Vector2(-1.0, 0.0))
	_check("digital m2", _approx(s.m2, 1.0))
	_check("digital |F|", _approx(s.force.length(), ForceMapper.DEFAULT_FMAX))
	_check("digital left", s.force.x < 0.0)
