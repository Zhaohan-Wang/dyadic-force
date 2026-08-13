extends Node
## 双语完整性与世界文字描边断言。
## 逐页实例化主要流程，确保中文模式无普通英文漏出、英文模式仍可切换。

const PAGES: Array[String] = [
	"res://scenes/title_screen.tscn",
	"res://scenes/experiment_setup_screen.tscn",
	"res://scenes/pairing_screen.tscn",
	"res://scenes/calibration_screen.tscn",
	"res://scenes/level_select.tscn",
	"res://scenes/results_screen.tscn",
]

const ZH_REQUIRED: Dictionary[String, String] = {
	"res://scenes/title_screen.tscn": "开始游戏",
	"res://scenes/experiment_setup_screen.tscn": "实验信息录入",
	"res://scenes/pairing_screen.tscn": "玩家配对",
	"res://scenes/calibration_screen.tscn": "输入检测",
	"res://scenes/level_select.tscn": "选择关卡",
	"res://scenes/results_screen.tscn": "通关！",
}

const EN_REQUIRED: Dictionary[String, String] = {
	"res://scenes/title_screen.tscn": "START GAME",
	"res://scenes/experiment_setup_screen.tscn": "EXPERIMENT SETUP",
	"res://scenes/pairing_screen.tscn": "PAIR UP",
	"res://scenes/calibration_screen.tscn": "INPUT CHECK",
	"res://scenes/level_select.tscn": "SELECT LEVEL",
	"res://scenes/results_screen.tscn": "LEVEL CLEAR!",
}

const ZH_BANNED: PackedStringArray = [
	"START GAME", "SETTINGS", "QUIT", "PAIR UP", "PRESS TO JOIN",
	"WAITING FOR PLAYERS", "INPUT CHECK", "HANDS OFF", "CENTER CHECK",
	"RANGE CHECK", "SELECT LEVEL", "NO TIMER", "LEVEL CLEAR", "TIME'S UP",
	"RETRY", "NEXT", "BACK", "CALIBRATION COMPLETE", "NO CALIBRATION NEEDED",
	"EXPERIMENT SETUP", "DYAD ID", "PARTICIPANT A ID", "LOCK & CONTINUE",
]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene_root: Window = get_tree().root
	var game_state: Node = scene_root.get_node("GameState")
	var input_hub: Node = scene_root.get_node("InputHub")
	input_hub.call("clear_slots")
	input_hub.call("join_slot", 0, 1)  # KEYBOARD_WASD
	input_hub.call("join_slot", 1, 2)  # KEYBOARD_ARROWS

	_prepare_result(game_state)
	for language: String in ["zh", "en"]:
		game_state.set("language", language)
		for page_path: String in PAGES:
			var packed: PackedScene = load(page_path) as PackedScene
			var page: Node = packed.instantiate()
			scene_root.add_child(page)
			await get_tree().process_frame
			await get_tree().process_frame
			if page_path == "res://scenes/title_screen.tscn":
				page.call("_open_settings")
				await get_tree().process_frame
				await get_tree().process_frame
			var visible_text: String = _collect_text(page)
			if language == "zh":
				_assert_zh_page(page_path, visible_text)
				if page_path == "res://scenes/title_screen.tscn":
					assert(visible_text.contains("手柄震动"), "haptic setting is not Chinese")
			else:
				assert(
					visible_text.contains(EN_REQUIRED[page_path]),
					"English page missing: %s" % page_path,
				)
				if page_path == "res://scenes/title_screen.tscn":
					assert(
						visible_text.contains("CONTROLLER VIBRATION"),
						"haptic setting is not English",
					)
			page.queue_free()
			await get_tree().process_frame

	_assert_level_resources(game_state)
	_assert_level_content(game_state, input_hub)
	_assert_pixel_outline()
	print("localization_assert OK")
	game_state.set("current_level", null)
	game_state.set("last_result", {})
	input_hub.call("clear_slots")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)

func _prepare_result(game_state: Node) -> void:
	game_state.set("dyad_id", "D001")
	game_state.set("participant_A", "A001")
	game_state.set("participant_B", "B001")
	game_state.set("relation_condition", "friends")
	game_state.set("participant_a_slot", 0)
	game_state.set("experiment_setup_locked", true)
	game_state.set("current_level", load("res://levels/level_1.tres"))
	game_state.set("last_result", {
		"success": true,
		"stars": 3,
		"level_name": "LEVEL 1 - MEADOW",
		"level_id": "level_1",
		"elapsed": 12.0,
		"hp": 3.0,
		"max_hp": 3.0,
		"hits": PackedVector2Array(),
		"trail": PackedVector2Array([Vector2.ZERO, Vector2(100, 0)]),
		"failed_trails": [],
		"spawn": Vector2.ZERO,
		"goal": Vector2(100, 0),
		"island": Vector2(200, 100),
		"avg_force": 2.5,
		"full_push_ratio": 0.2,
		"fine_control_ratio": 0.5,
		"experiment_condition": "baseline",
	})

func _collect_text(node: Node) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if node is Label:
		var label: Label = node as Label
		if label.visible and not label.text.is_empty():
			lines.append(label.text)
	elif node is Button:
		var button: Button = node as Button
		if button.visible and not button.text.is_empty():
			lines.append(button.text)
	for child: Node in node.get_children():
		lines.append(_collect_text(child))
	return "\n".join(lines)

func _assert_zh_page(page_path: String, visible_text: String) -> void:
	assert(
		visible_text.contains(ZH_REQUIRED[page_path]),
		"Chinese page missing: %s" % page_path,
	)
	for banned: String in ZH_BANNED:
		assert(
			not visible_text.contains(banned),
			"Chinese page leaks '%s': %s" % [banned, page_path],
		)

func _assert_level_content(game_state: Node, input_hub: Node) -> void:
	game_state.set("language", "zh")
	game_state.set("current_level", load("res://levels/level_1.tres"))
	input_hub.set("input_frozen", false)
	var packed: PackedScene = load("res://scenes/level.tscn") as PackedScene
	var level: Node = packed.instantiate()
	get_tree().root.add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var visible_text: String = _collect_text(level)
	assert(visible_text.contains("准备开始！"), "level intro title is not Chinese")
	assert(visible_text.contains("正式关卡有时间限制！"), "level intro line is not Chinese")
	assert(not visible_text.contains("GET READY!"), "level intro leaks English title")
	level.queue_free()
	await get_tree().process_frame

func _assert_level_resources(game_state: Node) -> void:
	game_state.set("language", "zh")
	var paths: PackedStringArray = [
		"res://levels/practice.tres",
		"res://levels/level_1.tres",
		"res://levels/level_2.tres",
		"res://levels/level_3.tres",
		"res://levels/level_4.tres",
		"res://levels/level_5.tres",
	]
	for path: String in paths:
		var definition: LevelDef = load(path) as LevelDef
		var source_lines: PackedStringArray = PackedStringArray([definition.level_name])
		source_lines.append_array(definition.intro_lines)
		source_lines.append_array(definition.tutorial_steps)
		for source: String in source_lines:
			var translated: String = str(game_state.call("localize_content", source))
			assert(translated != source, "level text lacks Chinese mapping: %s" % source)
			assert(_contains_cjk(translated), "level translation is not Chinese: %s" % translated)

func _contains_cjk(text: String) -> bool:
	for index: int in text.length():
		var codepoint: int = text.unicode_at(index)
		if codepoint >= 0x3400 and codepoint <= 0x9FFF:
			return true
	return false

func _assert_pixel_outline() -> void:
	var world_text: Control = MenuKit.make_world_caption("练习 00:00", 28)
	add_child(world_text)
	assert(world_text.get_child_count() >= 25, "pixel outline layers are incomplete")
	var face: Label = world_text.get_node_or_null("Face") as Label
	assert(face != null, "pixel outline face layer missing")
	for child: Node in world_text.get_children():
		var layer: Label = child as Label
		assert(layer != null and layer.label_settings.outline_size == 0, "Godot outline leaked")
	world_text.free()
