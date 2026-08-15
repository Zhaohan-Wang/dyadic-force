extends SceneTree
## 为 README 生成可入库的封面和五关特写。
## 用法：godot --headless --path . --script res://tools/compose_readme_images.gd

const LayoutProbe: GDScript = preload("res://tools/layout_probe.gd")
const OUT_DIR: String = "res://docs/readme"
const HERO_SIZE: Vector2i = Vector2i(1440, 720)
const THUMB_SIZE: Vector2i = Vector2i(448, 280)
const LEVELS: PackedStringArray = [
	"res://levels/level_1.tres",
	"res://levels/level_2.tres",
	"res://levels/level_3.tres",
	"res://levels/level_4.tres",
	"res://levels/level_5.tres",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_write_hero()
	_write_level_strip()
	print("compose_readme_images OK")
	quit(0)

func _write_hero() -> void:
	var bg: Image = _load_image("res://assets/ui/title_bg.jpg")
	var logo: Image = _load_image("res://assets/ui/title_logo.png")
	var crop: Rect2i = _banner_crop(bg.get_size(), HERO_SIZE)
	var hero: Image = bg.get_region(crop)
	hero.resize(HERO_SIZE.x, HERO_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var logo_size: Vector2i = Vector2i(518, 286)
	logo.resize(logo_size.x, logo_size.y, Image.INTERPOLATE_NEAREST)
	var dest: Vector2i = Vector2i(
		int((HERO_SIZE.x - logo_size.x) * 0.5),
		42,
	)
	hero.blend_rect(logo, Rect2i(Vector2i.ZERO, logo_size), dest)
	hero.save_jpg(ProjectSettings.globalize_path("%s/hero.jpg" % OUT_DIR), 0.88)
	print("  wrote hero.jpg %dx%d" % [hero.get_width(), hero.get_height()])

func _write_level_strip() -> void:
	var holder: Node2D = Node2D.new()
	root.add_child(holder)
	for index: int in LEVELS.size():
		var def: LevelDef = load(LEVELS[index]) as LevelDef
		var probe: LayoutProbe = LayoutProbe.new()
		probe.build(def, holder)
		var thumb: Image = _level_thumb(probe.render_art(), def.spawn_point)
		thumb.save_jpg(
			ProjectSettings.globalize_path("%s/level_%d.jpg" % [OUT_DIR, index + 1]),
			0.9,
		)
		print("  wrote level_%d.jpg" % (index + 1))
		for child: Node in holder.get_children():
			child.queue_free()
	holder.queue_free()

func _level_thumb(art: Image, spawn: Vector2) -> Image:
	var crop_size: Vector2i = Vector2i(
		mini(THUMB_SIZE.x * 2, art.get_width()),
		mini(THUMB_SIZE.y * 2, art.get_height()),
	)
	var crop_at: Vector2i = Vector2i(
		clampi(int(spawn.x) - int(crop_size.x * 0.28), 0, maxi(0, art.get_width() - crop_size.x)),
		clampi(int(spawn.y) - int(crop_size.y * 0.42), 0, maxi(0, art.get_height() - crop_size.y)),
	)
	var crop: Image = art.get_region(Rect2i(crop_at, crop_size))
	crop.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_NEAREST)
	return crop

func _banner_crop(source: Vector2i, target: Vector2i) -> Rect2i:
	var scale: float = maxf(
		float(target.x) / float(source.x),
		float(target.y) / float(source.y),
	)
	var sized: Vector2i = Vector2i(
		mini(source.x, int(ceil(float(target.x) / scale))),
		mini(source.y, int(ceil(float(target.y) / scale))),
	)
	return Rect2i(
		Vector2i(maxi(0, int((source.x - sized.x) * 0.5)), maxi(0, int((source.y - sized.y) * 0.18))),
		sized,
	)

func _load_image(path: String) -> Image:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
