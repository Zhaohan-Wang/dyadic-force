class_name ForceMapper
extends RefCounted
## 实验协议的连续虚拟作用力映射（§6.2）。
## 纯函数，不做实时低通；参数默认 d=0.12、γ=1.6、Fmax=8.0。

## 径向死区（中心漂移忽略阈值）
const DEFAULT_DEADZONE: float = 0.12
## 灵敏度指数：γ>1 时中段更软、满幅仍可达 Fmax
const DEFAULT_GAMMA: float = 1.6
## 实验虚拟作用力上限（日志与分析用此量纲）
const DEFAULT_FMAX: float = 8.0

## 单次采样结果：原始轴 → 校准 → 死区/曲线 → 最终力，全部可复算。
class Sample:
	## 硬件原始轴（中心偏移前）
	var raw: Vector2 = Vector2.ZERO
	## 减去中心偏移后的向量
	var calibrated: Vector2 = Vector2.ZERO
	## 径向幅值 |calibrated|
	var m: float = 0.0
	## 死区重映射后的归一化幅值
	var m1: float = 0.0
	## 灵敏度曲线后的幅值 m1^γ
	var m2: float = 0.0
	## 槽位增益（第 3 关扰动时 <1）
	var gain: float = 1.0
	## 最终虚拟作用力向量 F = Fmax · m2 · r/m · gain
	var force: Vector2 = Vector2.ZERO
	## 供 UI/动画使用的单位化力度方向（force / Fmax）
	var move: Vector2 = Vector2.ZERO

	func _init(
		p_raw: Vector2 = Vector2.ZERO,
		p_calibrated: Vector2 = Vector2.ZERO,
		p_m: float = 0.0,
		p_m1: float = 0.0,
		p_m2: float = 0.0,
		p_gain: float = 1.0,
		p_force: Vector2 = Vector2.ZERO,
		p_move: Vector2 = Vector2.ZERO,
	) -> void:
		raw = p_raw
		calibrated = p_calibrated
		m = p_m
		m1 = p_m1
		m2 = p_m2
		gain = p_gain
		force = p_force
		move = p_move

## 对已减去中心偏移的摇杆向量执行径向死区 + γ 曲线映射。
## center_offset 已在外部扣除；gain 在曲线之后乘到力上。
static func map_stick(
	raw: Vector2,
	center_offset: Vector2 = Vector2.ZERO,
	gain: float = 1.0,
	deadzone: float = DEFAULT_DEADZONE,
	gamma: float = DEFAULT_GAMMA,
	f_max: float = DEFAULT_FMAX,
) -> Sample:
	var calibrated: Vector2 = raw - center_offset
	var m: float = calibrated.length()
	var clamped_gain: float = clampf(gain, 0.0, 1.0)
	if m <= deadzone:
		return Sample.new(raw, calibrated, m, 0.0, 0.0, clamped_gain, Vector2.ZERO, Vector2.ZERO)
	var m1: float = (m - deadzone) / maxf(1.0 - deadzone, 0.0001)
	m1 = clampf(m1, 0.0, 1.0)
	var m2: float = pow(m1, gamma)
	var direction: Vector2 = calibrated / m
	var force: Vector2 = direction * f_max * m2 * clamped_gain
	var move: Vector2 = force / maxf(f_max, 0.0001)
	return Sample.new(raw, calibrated, m, m1, m2, clamped_gain, force, move)

## 数字输入（键盘 / 十字键）：满幅方向，m=m1=m2=1。
static func map_digital(
	direction: Vector2,
	gain: float = 1.0,
	f_max: float = DEFAULT_FMAX,
) -> Sample:
	if direction == Vector2.ZERO:
		return Sample.new()
	var dir: Vector2 = direction.normalized()
	var clamped_gain: float = clampf(gain, 0.0, 1.0)
	var force: Vector2 = dir * f_max * clamped_gain
	return Sample.new(dir, dir, 1.0, 1.0, 1.0, clamped_gain, force, force / maxf(f_max, 0.0001))
