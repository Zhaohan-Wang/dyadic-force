class_name PhysicsTuning
extends RefCounted
## 球物理调试参数：内存态 + 本地文件。
## 路径：user://physics_tuning/ball_physics.cfg
## 该文件独立于游戏进度，便于导出后再贴回工程固化。

const FILE_PATH: String = "user://physics_tuning/ball_physics.cfg"
const DIR_NAME: String = "physics_tuning"

## 与 scenes/level.tscn 球节点保持一致的系统默认值。
const DEFAULTS: Dictionary = {
	"normal_accel": 150.0,
	"tangent_accel": 145.0,
	"static_friction": 145.0,
	"kinetic_friction": 30.0,
	"rest_speed": 8.0,
	"traction_floor": 0.35,
	"input_rise_joy": 0.10,
	"input_rise_digital": 0.16,
	"input_release": 0.08,
	"idle_contact_friction": 28.0,
	"idle_contact_drag": 0.50,
	"idle_contact_soft_speed": 12.0,
	"idle_grip_engage": 0.7,
	"idle_grip_release": 12.0,
	"coasting_grip_factor": 0.05,
	"mass": 1.0,
	"linear_damp": 0.40,
	"angular_damp": 0.42,
	"material_friction": 0.42,
	"material_bounce": 0.38,
	"impact_threshold": 85.0,
}

## 局内调试滑条只暴露影响手感的重点参数（一页能调完）。
## 其余 DEFAULTS 仍会随存档读写，只是不进 UI。
const SPECS: Array[Dictionary] = [
	{"key": "normal_accel", "zh": "推力", "en": "PUSH", "min": 40.0, "max": 320.0, "step": 1.0},
	{"key": "tangent_accel", "zh": "扭转", "en": "SPIN", "min": 40.0, "max": 320.0, "step": 1.0},
	{"key": "static_friction", "zh": "起步门槛", "en": "START GRIP", "min": 40.0, "max": 320.0, "step": 1.0},
	{"key": "kinetic_friction", "zh": "滚动摩擦", "en": "ROLL DRAG", "min": 0.0, "max": 120.0, "step": 1.0},
	{"key": "traction_floor", "zh": "失配抓地", "en": "TRACTION", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "linear_damp", "zh": "线阻尼", "en": "DAMP", "min": 0.0, "max": 2.0, "step": 0.02},
	{"key": "mass", "zh": "质量", "en": "MASS", "min": 0.2, "max": 3.0, "step": 0.05},
	{"key": "material_bounce", "zh": "弹性", "en": "BOUNCE", "min": 0.0, "max": 1.0, "step": 0.01},
]

static var _values: Dictionary = {}
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_values = DEFAULTS.duplicate(true)
	_loaded = true
	load_from_disk()

static func values() -> Dictionary:
	ensure_loaded()
	return _values

static func get_value(key: String) -> float:
	ensure_loaded()
	return float(_values.get(key, DEFAULTS.get(key, 0.0)))

static func set_value(key: String, value: float) -> void:
	ensure_loaded()
	if not DEFAULTS.has(key):
		return
	_values[key] = _clamp_key(key, value)

static func reset_to_defaults() -> void:
	ensure_loaded()
	_values = DEFAULTS.duplicate(true)

static func absolute_path() -> String:
	return ProjectSettings.globalize_path(FILE_PATH)

static func load_from_disk() -> bool:
	ensure_loaded()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(FILE_PATH) != OK:
		return false
	for key: Variant in DEFAULTS.keys():
		var key_name: String = str(key)
		_values[key_name] = _clamp_key(
			key_name,
			float(cfg.get_value("ball", key_name, DEFAULTS[key_name])),
		)
	return true

static func save_to_disk() -> bool:
	ensure_loaded()
	var root: DirAccess = DirAccess.open("user://")
	if root == null:
		push_error("PhysicsTuning: cannot open user://")
		return false
	if root.make_dir_recursive(DIR_NAME) != OK and not DirAccess.dir_exists_absolute(
		"user://".path_join(DIR_NAME)
	):
		push_error("PhysicsTuning: cannot create physics_tuning directory")
		return false
	var cfg: ConfigFile = ConfigFile.new()
	for key: Variant in DEFAULTS.keys():
		var key_name: String = str(key)
		cfg.set_value("ball", key_name, float(_values.get(key_name, DEFAULTS[key_name])))
	var error: Error = cfg.save(FILE_PATH)
	if error != OK:
		push_error("PhysicsTuning: save failed (%s)" % error)
		return false
	return true

## 把当前调参写到关卡球上；调试关与正式关共用同一套值。
static func apply_to_ball(ball: PixelBall) -> void:
	if ball == null:
		return
	ensure_loaded()
	ball.normal_accel = get_value("normal_accel")
	ball.tangent_accel = get_value("tangent_accel")
	ball.static_friction = get_value("static_friction")
	ball.kinetic_friction = get_value("kinetic_friction")
	ball.rest_speed = get_value("rest_speed")
	ball.traction_floor = get_value("traction_floor")
	ball.input_rise_joy = get_value("input_rise_joy")
	ball.input_rise_digital = get_value("input_rise_digital")
	ball.input_release = get_value("input_release")
	ball.idle_contact_friction = get_value("idle_contact_friction")
	ball.idle_contact_drag = get_value("idle_contact_drag")
	ball.idle_contact_soft_speed = get_value("idle_contact_soft_speed")
	ball.idle_grip_engage = get_value("idle_grip_engage")
	ball.idle_grip_release = get_value("idle_grip_release")
	ball.coasting_grip_factor = get_value("coasting_grip_factor")
	ball.mass = get_value("mass")
	ball.linear_damp = get_value("linear_damp")
	ball.angular_damp = get_value("angular_damp")
	ball.impact_threshold = get_value("impact_threshold")
	ball.inertia = 0.4 * ball.mass * ball.ball_radius * ball.ball_radius
	var material: PhysicsMaterial = ball.physics_material_override
	if material == null:
		material = PhysicsMaterial.new()
		ball.physics_material_override = material
	else:
		material = material.duplicate() as PhysicsMaterial
		ball.physics_material_override = material
	material.friction = get_value("material_friction")
	material.bounce = get_value("material_bounce")

static func _clamp_key(key: String, value: float) -> float:
	for spec: Dictionary in SPECS:
		if str(spec["key"]) == key:
			return clampf(value, float(spec["min"]), float(spec["max"]))
	return value

static func format_value(key: String, value: float) -> String:
	var step: float = 1.0
	for spec: Dictionary in SPECS:
		if str(spec["key"]) == key:
			step = float(spec["step"])
			break
	if step >= 1.0:
		return "%d" % int(round(value))
	if step >= 0.1:
		return "%.1f" % value
	return "%.2f" % value
