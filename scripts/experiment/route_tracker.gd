class_name RouteTracker
extends RefCounted
## 纯路线投影器。原始球心始终另存，任何派生路线字段都可离线重算。

const LOCAL_SEARCH_RADIUS: int = 2
const MAX_PROGRESS_ROLLBACK: float = 0.01

var _points: PackedVector2Array = PackedVector2Array()
var _cumulative: PackedFloat32Array = PackedFloat32Array()
var _total_length: float = 0.0
var _corridor_half_width: float = 0.0
var _last_segment: int = -1
var _last_progress: float = 0.0
var _max_progress: float = 0.0

func configure(centerline: PackedVector2Array, corridor_half_width: float) -> void:
	_points = centerline.duplicate()
	_corridor_half_width = maxf(corridor_half_width, 0.0)
	_cumulative = PackedFloat32Array()
	_total_length = 0.0
	for i: int in _points.size():
		_cumulative.append(_total_length)
		if i + 1 < _points.size():
			_total_length += _points[i].distance_to(_points[i + 1])
	_last_segment = -1
	_last_progress = 0.0
	_max_progress = 0.0

func sample(point: Vector2) -> Dictionary:
	if _points.size() < 2 or _total_length <= 0.0:
		return empty_result()
	var first: int = 0
	var last: int = _points.size() - 2
	if _last_segment >= 0:
		first = maxi(0, _last_segment - LOCAL_SEARCH_RADIUS)
		last = mini(last, _last_segment + LOCAL_SEARCH_RADIUS)
	var result: Dictionary = _project_range(point, first, last)
	# 瞬移/重生后局部窗口可能不再包含真实最近段，此时回退全路线。
	if (
		_last_segment >= 0
		and float(result["distance"]) > maxf(_corridor_half_width * 2.5, 96.0)
	):
		result = _project_range(point, 0, _points.size() - 2)
	var raw_progress: float = float(result["raw_progress"])
	var progress: float = maxf(raw_progress, _last_progress - MAX_PROGRESS_ROLLBACK)
	progress = clampf(progress, 0.0, 1.0)
	_last_progress = progress
	_max_progress = maxf(_max_progress, progress)
	_last_segment = int(result["segment"])
	result["progress"] = progress
	result["max_progress"] = _max_progress
	result["inside_boundary"] = float(result["distance"]) <= _corridor_half_width
	return result

func reset_life() -> void:
	_last_segment = -1
	_last_progress = 0.0

static func project_point(
	point: Vector2,
	centerline: PackedVector2Array,
	corridor_half_width: float,
) -> Dictionary:
	var tracker: RouteTracker = RouteTracker.new()
	tracker.configure(centerline, corridor_half_width)
	return tracker.sample(point)

static func empty_result() -> Dictionary:
	return {
		"error": Vector2.ZERO,
		"signed_error": 0.0,
		"distance": 0.0,
		"raw_progress": 0.0,
		"progress": 0.0,
		"max_progress": 0.0,
		"inside_boundary": true,
		"segment": -1,
		"nearest": Vector2.ZERO,
		"tangent": Vector2.ZERO,
	}

func _project_range(point: Vector2, first: int, last: int) -> Dictionary:
	var best_distance_sq: float = INF
	var best: Dictionary = empty_result()
	for segment: int in range(first, last + 1):
		var start: Vector2 = _points[segment]
		var finish: Vector2 = _points[segment + 1]
		var edge: Vector2 = finish - start
		var edge_length_sq: float = edge.length_squared()
		if edge_length_sq <= 0.000001:
			continue
		var t: float = clampf((point - start).dot(edge) / edge_length_sq, 0.0, 1.0)
		var nearest: Vector2 = start + edge * t
		var error: Vector2 = point - nearest
		var distance_sq: float = error.length_squared()
		if distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		var edge_length: float = sqrt(edge_length_sq)
		var tangent: Vector2 = edge / edge_length
		best = {
			"error": error,
			"signed_error": tangent.cross(error),
			"distance": sqrt(distance_sq),
			"raw_progress": (
				float(_cumulative[segment]) + edge_length * t
			) / _total_length,
			"segment": segment,
			"nearest": nearest,
			"tangent": tangent,
		}
	return best
