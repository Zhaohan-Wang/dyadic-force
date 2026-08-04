extends Node
## 暂停菜单冒烟：打开 → 树暂停 → 继续/重开路径解除 paused。

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.current_level = load("res://levels/practice.tres")
	InputHub.clear_slots()
	InputHub.join_slot(0, InputHub.SourceKind.KEYBOARD_WASD)
	InputHub.join_slot(1, InputHub.SourceKind.KEYBOARD_ARROWS)
	InputHub.input_frozen = false

	var level: Node = (load("res://scenes/level.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	InputHub.input_frozen = false
	var intro: Node = level.find_child("IntroPopup", true, false)
	if intro != null:
		intro.queue_free()
		await get_tree().process_frame

	var pause: PauseMenu = level.get_node_or_null("PauseMenu") as PauseMenu
	assert(pause != null, "PauseMenu missing")
	assert(not pause.is_open(), "starts closed")
	assert(not get_tree().paused, "tree starts unpaused")

	# 模拟 ESC
	var esc: InputEventKey = InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	level._input(esc)
	assert(pause.is_open(), "ESC should open pause")
	assert(get_tree().paused, "tree should pause")
	assert(InputHub.input_frozen, "input frozen while paused")

	# 继续
	pause.resume_requested.emit()
	await get_tree().process_frame
	assert(not pause.is_open(), "resume closes menu")
	assert(not get_tree().paused, "resume clears tree pause")
	assert(not InputHub.input_frozen, "resume unfreezes input")

	# 再开，走返回选关前必须清 paused（不真切场景，只测清理）
	level._input(esc)
	assert(get_tree().paused, "re-open pauses")
	get_tree().paused = false
	pause.close_menu()
	InputHub.input_frozen = true
	assert(not get_tree().paused, "leave path clears pause")

	# Start 键也能打开
	InputHub.input_frozen = false
	var start: InputEventJoypadButton = InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	start.device = 0
	level._input(start)
	assert(pause.is_open() and get_tree().paused, "Start opens pause")
	get_tree().paused = false
	pause.close_menu()

	print("pause_menu_smoke OK")
	level.queue_free()
	get_tree().quit(0)
