extends SceneTree
## 按需生成扰动人工复核包：qc/review_queue.csv、SVG 与 review_report.json。
## 用法：godot --headless --path . --script res://tools/generate_review_package.gd -- --session-dir <目录>

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var directory: String = ""
	for i: int in arguments.size():
		if arguments[i] == "--session-dir" and i + 1 < arguments.size():
			directory = arguments[i + 1]
			break
	if directory.is_empty():
		push_error("Usage: --session-dir <user:// path or absolute path>")
		quit(2)
		return
	if not DirAccess.dir_exists_absolute(directory):
		push_error("Session directory does not exist: %s" % directory)
		quit(2)
		return
	var paths: Dictionary = ExperimentLog.resolve_session_paths(directory)
	if not ExperimentAnalyzer.export_review_package(paths):
		push_error("Review package failed: %s" % directory)
		quit(1)
		return
	print("EXPERIMENT_REVIEW_OK directory=%s qc=%s" % [directory, paths["qc_directory"]])
	quit(0)
