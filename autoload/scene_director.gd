extends Node
## 场景切换导演：统一管理场景跳转与简单淡入淡出。

## 转场层（全屏黑遮罩）
var _fade: ColorRect
var _busy: bool = false

func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	layer.name = "TransitionLayer"
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.06, 0.05, 0.04, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

## 带淡入淡出的场景切换
func go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	await _tween_fade(1.0, 0.25)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await _tween_fade(0.0, 0.30)
	_busy = false

## 直接切换（无转场，用于调试）
func go_to_immediate(path: String) -> void:
	get_tree().change_scene_to_file(path)

## 淡入/淡出遮罩
func _tween_fade(target_alpha: float, duration: float) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if target_alpha > 0.5 else Control.MOUSE_FILTER_IGNORE
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", target_alpha, duration)
	await tween.finished
