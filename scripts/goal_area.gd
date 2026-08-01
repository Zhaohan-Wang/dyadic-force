class_name GoalArea
extends Area2D
## 终点区域：球进入并停留 hold_time 秒后发出 reached。

signal reached

## 需要停留的时间（秒）
@export var hold_time: float = 0.5

var _things_tex: Texture2D = preload("res://assets/objects/grass_biome_things.png")
var _hold: float = 0.0
var _ball_inside: bool = false
var _armed: bool = true

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1  # 默认层上的球
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()

## 在目标点构建视觉标记（旗帜式小树 + 地面圆）
func _build_visual() -> void:
	# 地面提示圈
	var marker: Sprite2D = Sprite2D.new()
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in 32:
		for x: int in 32:
			var dx: float = float(x) - 15.5
			var dy: float = float(y) - 15.5
			var d: float = sqrt(dx * dx + dy * dy)
			if d < 14.0 and d > 10.0:
				img.set_pixel(x, y, Color(0.95, 0.85, 0.35, 0.55))
			elif d <= 10.0:
				img.set_pixel(x, y, Color(0.95, 0.85, 0.35, 0.18))
	marker.texture = ImageTexture.create_from_image(img)
	marker.z_index = -1
	add_child(marker)

	# 用苹果树当终点旗杆
	var flag: Sprite2D = Sprite2D.new()
	flag.texture = _things_tex
	flag.region_enabled = true
	flag.region_rect = Rect2(48, 0, 32, 32)
	flag.offset = Vector2(0.0, -16.0)
	flag.z_index = 1
	add_child(flag)

	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 36.0
	shape.shape = circle
	add_child(shape)

func _physics_process(delta: float) -> void:
	if not _armed or not _ball_inside:
		_hold = 0.0
		return
	_hold += delta
	if _hold >= hold_time:
		_armed = false
		reached.emit()

func _on_body_entered(body: Node2D) -> void:
	if body is PixelBall:
		_ball_inside = true

func _on_body_exited(body: Node2D) -> void:
	if body is PixelBall:
		_ball_inside = false
		_hold = 0.0
