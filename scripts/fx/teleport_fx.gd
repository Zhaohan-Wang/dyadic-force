class_name TeleportFx
extends Node2D
## 独立传送演出容器：统一驱动前后两层，避免传送门本体改变 z_index。

## 完整演出时长（秒），与 Level 的角色上升时序对齐。
const DURATION: float = 1.45

var _age: float = 0.0
var _back: TeleportFxLayer
var _front: TeleportFxLayer

func _ready() -> void:
	_back = TeleportFxLayer.new()
	_back.name = "BackFx"
	_back.front = false
	_back.z_as_relative = false
	_back.z_index = -1  # 地面之上、球体之下
	add_child(_back)

	_front = TeleportFxLayer.new()
	_front.name = "FrontFx"
	_front.front = true
	_front.z_as_relative = false
	_front.z_index = 8  # 只让轨道光点与离场闪点压在角色前
	add_child(_front)

func _process(delta: float) -> void:
	_age += delta
	var progress: float = clampf(_age / DURATION, 0.0, 1.0)
	_back.set_progress(progress)
	_front.set_progress(progress)
	if progress >= 1.0:
		queue_free()

## 在世界坐标播放；FX 不继承传送门的地面 z 层。
static func play(parent: Node2D, world_position: Vector2) -> TeleportFx:
	var fx: TeleportFx = TeleportFx.new()
	fx.name = "TeleportFx"
	parent.add_child(fx)
	fx.global_position = world_position
	return fx
