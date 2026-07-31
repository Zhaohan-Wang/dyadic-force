class_name Spring2D
extends RefCounted
## 可复用的二维弹簧动画工具（对齐 iOS 的 duration/bounce 弹簧 API）。
##
## 参数换算（Apple SwiftUI Spring 的官方定义）：
##   mass      = 1
##   stiffness = (2π / duration)²
##   dampingRatio(ζ) = 1 - bounce          （bounce ≥ 0，0 为临界阻尼）
##   dampingRatio(ζ) = 1 / (1 + bounce)    （bounce < 0，过阻尼、更慢收敛）
##   damping   = 2 × ζ × √(stiffness × mass)
##
## 注：原文档 TS 里 "1 - 4π·bounce/duration" 的写法代入其自带预设
## （duration=0.5, bounce=0.3 → damping≈10）会得到负值，应为公式转录错误；
## 这里采用与预设表一致、量纲自洽的官方换算。
##
## 用法：
##   var spring: Spring2D = Spring2D.new(0.55, 0.15)
##   spring.reset(初始位置)
##   每帧: spring.target = 目标位置; 位置 = spring.update(delta)

var stiffness: float = 0.0            # 弹簧刚度
var damping: float = 0.0              # 阻尼系数
var mass: float = 1.0                 # 质量（固定为 1）

var position: Vector2 = Vector2.ZERO  # 弹簧当前位置
var velocity: Vector2 = Vector2.ZERO  # 弹簧当前速度
var target: Vector2 = Vector2.ZERO    # 追踪目标

func _init(duration: float, bounce: float) -> void:
	stiffness = pow(TAU / duration, 2.0) * mass
	var damping_ratio: float
	if bounce >= 0.0:
		damping_ratio = 1.0 - bounce
	else:
		damping_ratio = 1.0 / (1.0 + bounce)
	damping = 2.0 * damping_ratio * sqrt(stiffness * mass)

## 把弹簧重置到指定位置（速度清零，目标同步），用于初始化或瞬移
func reset(p_position: Vector2) -> void:
	position = p_position
	velocity = Vector2.ZERO
	target = p_position

## 推进一帧弹簧模拟并返回新位置。
## 使用半隐式欧拉积分（先更新速度、再更新位置），
## 在 60Hz 的物理帧率下数值稳定且足够精确。
func update(delta: float) -> Vector2:
	var accel: Vector2 = (stiffness * (target - position) - damping * velocity) / mass
	velocity += accel * delta
	position += velocity * delta
	return position
