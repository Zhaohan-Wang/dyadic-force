extends Node
## 用假结算数据验证：面板包得住全部统计，且已删除字段不再出现。

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.language = GameState.LANGUAGE_ZH
	GameState.last_result = {
		"success": true,
		"stars": 2,
		"level_id": "practice",
		"level_name": "练习场",
		"elapsed": 125.4,
		"time_left": 0.0,
		"timed": false,
		"hp": 1.5,
		"max_hp": 3.0,
		"island": Vector2(800, 480),
		"trail": PackedVector2Array([Vector2(80, 80), Vector2(220, 140), Vector2(400, 200)]),
		"failed_trails": [],
		"hits": PackedVector2Array([Vector2(180, 120)]),
		"spawn": Vector2(80, 80),
		"goal": Vector2(400, 200),
		"avg_force": 3.47,
		"full_push_ratio": 0.42,
		"fine_control_ratio": 0.28,
		"experiment_condition": "baseline",
	}
	get_tree().change_scene_to_file("res://scenes/results_screen.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var scene: Node = get_tree().current_scene
	var texts: Array[String] = []
	_collect_label_texts(scene, texts)
	var joined: String = " | ".join(texts)
	assert(not joined.contains("稳定性") and not joined.contains("RIDE"), "stability row still present")
	assert(not joined.contains("实验条件"), "condition row still present")
	assert(joined.contains("精细控制"), "fine control should remain")
	assert(joined.contains("02:05"), "time value missing: %s" % joined)

	var panel: NinePatchRect = null
	for child: Node in scene.get_children():
		if child is NinePatchRect:
			panel = child as NinePatchRect
			break
	assert(panel != null, "panel missing")
	# 面板应高于内容区，精细控制必须落在面板底边之上
	var fine_label: Label = _find_label(scene, "精细控制")
	assert(fine_label != null, "fine control label missing")
	var fine_bottom: float = fine_label.get_global_rect().end.y
	var panel_bottom: float = panel.get_global_rect().end.y
	assert(
		fine_bottom <= panel_bottom - 8.0,
		"fine control overflows panel: fine=%.1f panel=%.1f" % [fine_bottom, panel_bottom]
	)

	print(
		"capture_results OK panel_h=%.0f fine_bottom=%.0f panel_bottom=%.0f"
		% [panel.size.y, fine_bottom, panel_bottom]
	)
	get_tree().quit(0)

func _collect_label_texts(node: Node, out: Array[String]) -> void:
	var label: Label = node as Label
	if label != null:
		out.append(label.text)
	for child: Node in node.get_children():
		_collect_label_texts(child, out)

func _find_label(node: Node, text: String) -> Label:
	var label: Label = node as Label
	if label != null and label.text == text:
		return label
	for child: Node in node.get_children():
		var found: Label = _find_label(child, text)
		if found != null:
			return found
	return null
