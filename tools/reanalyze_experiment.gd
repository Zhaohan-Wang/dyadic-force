extends SceneTree
## 从不可变 raw CSV 重算派生结果。
## 用法：godot --headless --path . --script res://tools/reanalyze_experiment.gd -- --session-dir <目录>

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
	if not ExperimentAnalyzer.export_session(paths):
		push_error("Reanalysis failed: %s" % directory)
		quit(1)
		return
	print("EXPERIMENT_REANALYSIS_OK directory=%s" % directory)
	quit(0)
