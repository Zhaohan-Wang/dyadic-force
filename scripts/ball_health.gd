class_name BallHealth
extends Node
## 挂在球上：撞击按力度扣半心浮点伤、无敌帧、受击闪红、重生闪白与闪烁。
## HUD 固定 3 格；弱撞 0.5、中撞 1.0、重撞最高 1.5。

## 冲击速度低于此值不扣血（轻微蹭墙不掉血）
@export var damage_threshold: float = 100.0
## 弱撞上限：低于它才算弱撞（扣半心）；再往上默认就是中撞
@export var weak_limit: float = 150.0
## 重撞下限：速度突变超过它算重撞（扣一心半）
@export var heavy_limit: float = 300.0
## 受击无敌时长（秒）
@export var i_frame_duration: float = 0.7
## 重生后无敌时长（秒）——参考 Celeste / Mario 的闪烁无敌
@export var spawn_i_frame_duration: float = 1.6

signal damaged(amount: float, remaining_hp: float)
signal died

var _state: LevelState
var _ball: PixelBall
var _i_frames: float = 0.0
var _flash: float = 0.0
var _spawn_flash: float = 0.0
## 重生闪烁阶段剩余时间
var _blink_left: float = 0.0

func setup(ball: PixelBall, state: LevelState) -> void:
	_ball = ball
	_state = state
	if not _ball.impacted.is_connected(_on_impacted):
		_ball.impacted.connect(_on_impacted)

func _process(delta: float) -> void:
	if _i_frames > 0.0:
		_i_frames = maxf(0.0, _i_frames - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	if _spawn_flash > 0.0:
		_spawn_flash = maxf(0.0, _spawn_flash - delta)
	if _blink_left > 0.0:
		_blink_left = maxf(0.0, _blink_left - delta)
		_apply_blink()
	elif _ball != null and not _ball.visible:
		pass
	else:
		_clear_blink_modulate()
	_push_shader_flash()

func _on_impacted(strength: float) -> void:
	if _state == null or _ball == null:
		return
	if _state.phase != LevelState.Phase.RUNNING and _state.phase != LevelState.Phase.READY:
		return
	if _i_frames > 0.0:
		return
	if strength < damage_threshold:
		return
	# 三档判定：默认中撞扣 1 心；只有很轻才算弱撞，快撞直接算重撞
	var amount: float = 1.0
	if strength < weak_limit:
		amount = 0.5
	elif strength >= heavy_limit:
		amount = 1.5
	_i_frames = i_frame_duration
	_flash = 0.35
	_push_shader_flash()
	var dead: bool = _state.apply_damage(amount)
	damaged.emit(amount, _state.hp)
	if dead:
		died.emit()

## 重生时调用：短暂闪白 + 闪烁无敌（期间不会再受伤）
func begin_spawn_protection() -> void:
	_i_frames = spawn_i_frame_duration
	_spawn_flash = 0.35
	_blink_left = spawn_i_frame_duration
	_push_shader_flash()

## 死亡瞬间清掉视觉反馈（球会被隐藏）
func clear_visuals() -> void:
	_flash = 0.0
	_spawn_flash = 0.0
	_blink_left = 0.0
	_push_shader_flash()
	_clear_blink_modulate()

## 闪烁：约 8Hz 透明度切换（经典平台机无敌表现）
func _apply_blink() -> void:
	if _ball == null:
		return
	var blink_on: bool = int(_blink_left * 10.0) % 2 == 0
	_ball.modulate.a = 1.0 if blink_on else 0.35

func _clear_blink_modulate() -> void:
	if _ball == null:
		return
	if _blink_left <= 0.0 and _ball.modulate.a < 1.0:
		_ball.modulate.a = 1.0

## 把闪红 / 闪白推给球 shader
func _push_shader_flash() -> void:
	if _ball == null:
		return
	var sprite: Sprite2D = _ball.get_node_or_null("BallSprite") as Sprite2D
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	mat.set_shader_parameter("damage_flash", clampf(_flash / 0.35, 0.0, 1.0))
	mat.set_shader_parameter("spawn_flash", clampf(_spawn_flash / 0.35, 0.0, 1.0))
