extends SceneTree
## 四页教学界面冒烟：资源、布局、页序与末页文案。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	(root.get_node("GameState") as Node).set("language", "zh")
	var packed: PackedScene = load("res://scenes/guide_screen.tscn") as PackedScene
	assert(packed != null, "guide scene missing")
	var page: Control = packed.instantiate() as Control
	root.add_child(page)
	await process_frame
	await process_frame

	assert(int(page.get("_page")) == 0, "guide must start on page 1")
	var image: TextureRect = page.get("_image") as TextureRect
	var previous: Button = page.get("_previous_button") as Button
	var next: Button = page.get("_next_button") as Button
	assert(image != null and image.texture != null, "first guide image missing")
	assert(image.texture.get_size() == Vector2(1024, 642), "guide image dimensions changed")
	assert(previous != null and previous.disabled, "previous must be disabled on first page")
	assert(next != null and next.text == "下一页", "first-page next copy mismatch")
	assert(
		previous.focus_mode == Control.FOCUS_NONE and next.focus_mode == Control.FOCUS_NONE,
		"guide buttons must not consume keyboard/gamepad accept",
	)

	var image_rect: Rect2 = image.get_global_rect()
	assert(image_rect.position.x >= 0.0 and image_rect.position.y >= 0.0, "guide image starts offscreen")
	assert(image_rect.end.x <= 1920.0 and image_rect.end.y <= 1080.0, "guide image ends offscreen")

	var accept_press: InputEventAction = InputEventAction.new()
	accept_press.action = &"ui_accept"
	accept_press.pressed = true
	page.call("_input", accept_press)
	assert(int(page.get("_page")) == 1, "accept press must advance exactly one page")
	var accept_release: InputEventAction = InputEventAction.new()
	accept_release.action = &"ui_accept"
	accept_release.pressed = false
	page.call("_input", accept_release)
	assert(int(page.get("_page")) == 1, "accept release must not advance the page")

	page.call("_next_page")
	page.call("_next_page")
	assert(int(page.get("_page")) == 3, "guide did not reach page 4")
	assert(next.text == "进入选关", "last-page action copy mismatch")
	assert(not previous.disabled, "previous must be enabled after page 1")
	page.call("_previous_page")
	assert(int(page.get("_page")) == 2, "previous did not return to page 3")

	page.queue_free()
	await process_frame
	print("GUIDE_SCREEN_ASSERT_OK")
	quit(0)
