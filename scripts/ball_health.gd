class_name BallHealth
extends Node
## 挂在球上：把 impacted 冲击换算成扣血，带无敌帧与闪红反馈。

## 冲击速度低于此值不扣血
@export var damage_threshold: float = 120.0
## 超过阈值后的伤害系数
@export var damage_scale: float = 0.12
## 单次最大伤害
@export var max_hit_damage: float = 28.0
## 无敌时长（秒）
@export var i_frame_duration: float = 0.55

signal damaged(amount: float, remaining_hp: float)
signal died

var _state: LevelState
var _ball: PixelBall
var _i_frames: float = 0.0
var _flash: float = 0.0

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
		_push_flash()

func _on_impacted(strength: float) -> void:
	if _state == null or _ball == null:
		return
	if _state.phase != LevelState.Phase.RUNNING and _state.phase != LevelState.Phase.READY:
		return
	if _i_frames > 0.0:
		return
	if strength < damage_threshold:
		return
	var amount: float = clampf((strength - damage_threshold) * damage_scale, 4.0, max_hit_damage)
	_i_frames = i_frame_duration
	_flash = 0.35
	_push_flash()
	var dead: bool = _state.apply_damage(amount)
	damaged.emit(amount, _state.hp)
	if dead:
		died.emit()

## 把闪红强度推给球 shader
func _push_flash() -> void:
	if _ball == null:
		return
	var sprite: Sprite2D = _ball.get_node_or_null("BallSprite") as Sprite2D
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	mat.set_shader_parameter("damage_flash", clampf(_flash / 0.35, 0.0, 1.0))
