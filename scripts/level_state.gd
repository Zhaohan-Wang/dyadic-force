class_name LevelState
extends RefCounted
## 本关可观察状态 store：HUD 只订阅信号，不互相引用。

enum Phase {
	READY,     # 进场等待第一次输入
	RUNNING,   # 正式进行中
	DEAD,      # 死亡重生过渡
	FINISHED,  # 已过关
	FAILED,    # 超时失败
}

signal hp_changed(hp: float, max_hp: float)
signal time_changed(time_left: float, elapsed: float, timed: bool)
signal phase_changed(phase: Phase)
signal tutorial_changed(step_index: int, text: String)
signal stars_changed(stars: int)

var phase: Phase = Phase.READY
var hp: float = 100.0
var max_hp: float = 100.0
var time_left: float = 0.0
var elapsed: float = 0.0
var timed: bool = false  # 是否倒计时模式
var tutorial_step: int = -1
var tutorial_texts: PackedStringArray = PackedStringArray()
var stars: int = 0

## 用关卡定义初始化状态
func setup(def: LevelDef) -> void:
	max_hp = def.ball_max_hp
	hp = max_hp
	timed = def.time_limit > 0.0
	time_left = def.time_limit
	elapsed = 0.0
	tutorial_texts = def.tutorial_steps
	tutorial_step = -1
	stars = 0
	_set_phase(Phase.READY)
	hp_changed.emit(hp, max_hp)
	time_changed.emit(time_left, elapsed, timed)

## 开始计时（球第一次受力时调用）
func start_running() -> void:
	if phase == Phase.READY:
		_set_phase(Phase.RUNNING)

## 扣血；返回是否死亡
func apply_damage(amount: float) -> bool:
	if phase != Phase.RUNNING and phase != Phase.READY:
		return false
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	return hp <= 0.0

## 回满血（重生时）
func refill_hp() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

## 推进时间；返回是否超时失败
func tick_time(delta: float) -> bool:
	if phase != Phase.RUNNING:
		return false
	elapsed += delta
	if timed:
		time_left = maxf(0.0, time_left - delta)
		time_changed.emit(time_left, elapsed, timed)
		if time_left <= 0.0:
			_set_phase(Phase.FAILED)
			return true
	else:
		time_changed.emit(time_left, elapsed, timed)
	return false

## 死亡惩罚扣时间
func apply_time_penalty(seconds: float) -> void:
	if timed and phase == Phase.RUNNING:
		time_left = maxf(0.0, time_left - seconds)
		time_changed.emit(time_left, elapsed, timed)

## 进入死亡过渡
func enter_dead() -> void:
	_set_phase(Phase.DEAD)

## 从死亡恢复到进行中
func revive() -> void:
	refill_hp()
	_set_phase(Phase.RUNNING)

## 过关并计算星级
func finish(remaining_hp_ratio: float) -> void:
	# 1 星通关；剩余时间/血量加星
	stars = 1
	if timed and time_left > 15.0:
		stars += 1
	elif not timed and elapsed < 90.0:
		stars += 1
	if remaining_hp_ratio > 0.5:
		stars += 1
	stars = mini(3, stars)
	stars_changed.emit(stars)
	_set_phase(Phase.FINISHED)

## 推进教程步骤
func advance_tutorial() -> void:
	if tutorial_texts.is_empty():
		return
	tutorial_step = mini(tutorial_step + 1, tutorial_texts.size() - 1)
	tutorial_changed.emit(tutorial_step, tutorial_texts[tutorial_step])

## 若尚未开始教程则显示第一步
func ensure_tutorial_started() -> void:
	if tutorial_texts.is_empty():
		return
	if tutorial_step < 0:
		tutorial_step = 0
		tutorial_changed.emit(tutorial_step, tutorial_texts[tutorial_step])

func _set_phase(p: Phase) -> void:
	phase = p
	phase_changed.emit(phase)
