extends SceneTree
## 跨 session 汇总实验表。
const Aggregator := preload("res://scripts/experiment/experiment_aggregator.gd")
## 用法：godot --headless --path . --script res://tools/aggregate_experiments.gd -- \
##   --root <experiments根目录> --out <输出目录> [--reanalyze-missing] [--dyad 101]

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var root_path: String = ""
	var out_path: String = ""
	var reanalyze_missing: bool = false
	var dyad_filter: String = ""
	for i: int in arguments.size():
		match arguments[i]:
			"--root":
				if i + 1 < arguments.size():
					root_path = arguments[i + 1]
			"--out":
				if i + 1 < arguments.size():
					out_path = arguments[i + 1]
			"--reanalyze-missing":
				reanalyze_missing = true
			"--dyad":
				if i + 1 < arguments.size():
					dyad_filter = arguments[i + 1]
	if root_path.is_empty():
		root_path = ProjectSettings.globalize_path("user://experiments")
	if out_path.is_empty():
		out_path = root_path.path_join("_aggregate")
	if not DirAccess.dir_exists_absolute(root_path):
		push_error("Experiments root does not exist: %s" % root_path)
		quit(2)
		return
	var report: Dictionary = Aggregator.new().aggregate(
		root_path, out_path, reanalyze_missing, dyad_filter
	)
	if not bool(report.get("ok", false)):
		push_error("Aggregation failed: %s" % out_path.path_join("aggregate_report.json"))
		quit(1)
		return
	var counts: Dictionary = report.get("counts", {}) as Dictionary
	print(
		"EXPERIMENT_AGGREGATE_OK sessions=%s trials=%s out=%s" % [
			counts.get("sessions", 0),
			counts.get("trials", 0),
			out_path,
		]
	)
	quit(0)
