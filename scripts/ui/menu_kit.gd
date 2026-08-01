class_name MenuKit
extends RefCounted
## 菜单 UI 工具库：统一使用 Sprout Lands UI 包与按键提示图集，
## 提供面板 / 大按钮 / 键帽 / 手柄键 / 图标 / 红心等构件工厂。
## 所有图集坐标都来自对素材的逐像素探测，勿随意改动。

# ---------- 设计色板（取自 Sprout Lands） ----------
## 面板上的深棕文字
const COL_INK: Color = Color("4a3325")
## 深色背景上的奶油白文字
const COL_CREAM: Color = Color("fdf2dc")
## 强调橙（选中 / 高亮）
const COL_ACCENT: Color = Color("e8912d")
## 就绪绿
const COL_READY: Color = Color("5f9e3c")
## 危险红
const COL_DANGER: Color = Color("c9564b")
## 文字描边棕
const COL_OUTLINE: Color = Color("3a2a1c")
## 背景草地双色
const COL_GRASS_A: Color = Color("74a648")
const COL_GRASS_B: Color = Color("6c9c42")

# ---------- 纹理与图集坐标 ----------
static var _font: FontFile = preload("res://assets/ui/pixel_font_sprout.ttf")
static var _tex_panel_src: Texture2D = preload("res://assets/ui/sprout_panel.png")
static var _tex_btn_big_src: Texture2D = preload("res://assets/ui/sprout_btn_big.png")
static var _tex_btn_square_src: Texture2D = preload("res://assets/ui/sprout_btn_square.png")
static var _tex_dialog_src: Texture2D = preload("res://assets/ui/sprout_dialog.png")
static var _tex_hearts: Texture2D = preload("res://assets/ui/sprout_hearts.png")
static var _tex_icons: Texture2D = preload("res://assets/ui/sprout_icons.png")
static var _tex_kb_keys: Texture2D = preload("res://assets/ui/kb_keys.png")
static var _tex_kb_symbols: Texture2D = preload("res://assets/ui/kb_symbols.png")
static var _tex_pad: Texture2D = preload("res://assets/ui/pad_xbox.png")

## 九宫格最近邻放大倍率：源素材圆角只有 2～3px，
## 直接用到 1080p 会几乎看不见；放大后阶梯圆角才清晰。
const PATCH_SCALE: int = 4

## 源图区域（未放大；探测值）
const PANEL_REGION_SRC: Rect2i = Rect2i(139, 12, 106, 122)
const BTN_REGION_NORMAL_SRC: Rect2i = Rect2i(3, 2, 90, 27)
const BTN_REGION_PRESSED_SRC: Rect2i = Rect2i(99, 4, 90, 25)
const BTN_SQUARE_REGION_SRC: Rect2i = Rect2i(11, 59, 26, 28)
const DIALOG_REGION_SRC: Rect2i = Rect2i(2, 7, 172, 35)

## 源图九宫格边距（覆盖 3px 阶梯圆角 + 边框，且不超过半宽/半高）
const PANEL_MARGIN_SRC: int = 8
const BTN_MARGIN_L_SRC: int = 8
const BTN_MARGIN_R_SRC: int = 8
const BTN_MARGIN_T_SRC: int = 6
const BTN_MARGIN_B_SRC: int = 8
const DIALOG_MARGIN_L_SRC: int = 14  # 左侧含对话尾巴
const DIALOG_MARGIN_R_SRC: int = 8
const DIALOG_MARGIN_T_SRC: int = 8
const DIALOG_MARGIN_B_SRC: int = 8

## 放大后的缓存纹理（首次使用时烘焙）
static var _tex_panel: Texture2D = null
static var _tex_btn_normal: Texture2D = null
static var _tex_btn_pressed: Texture2D = null
static var _tex_btn_square: Texture2D = null
static var _tex_dialog: Texture2D = null
## 红心三态区域：满 / 半 / 空
const HEART_REGIONS: Array[Rect2] = [
	Rect2(7, 25, 18, 16), Rect2(39, 25, 18, 16), Rect2(71, 25, 18, 16),
]
## 图标表（16x16 网格）中常用图标
const ICON_REGIONS: Dictionary = {
	"star_cream": Rect2(80, 0, 16, 16),
	"star_tan": Rect2(176, 0, 16, 16),
	"star_dark": Rect2(224, 0, 16, 16),
	"trophy_cream": Rect2(64, 16, 16, 16),
	"trophy_dark": Rect2(208, 16, 16, 16),
	"check_cream": Rect2(48, 32, 16, 16),
	"check_dark": Rect2(192, 32, 16, 16),
	"cross_cream": Rect2(64, 32, 16, 16),
	"cross_dark": Rect2(208, 32, 16, 16),
}
## 符号键表中的特殊键（16x16）
const SYMBOL_KEY_REGIONS: Dictionary = {
	"UP": Rect2(64, 192, 16, 16),
	"LEFT": Rect2(64, 208, 16, 16),
	"DOWN": Rect2(64, 224, 16, 16),
	"RIGHT": Rect2(64, 240, 16, 16),
	"ESC": Rect2(0, 0, 16, 16),
	"DEL": Rect2(64, 112, 16, 16),
}
## 手柄键（Xbox 布局，彩色列）
const PAD_REGIONS: Dictionary = {
	"a": Rect2(0, 64, 16, 16),
	"b": Rect2(0, 96, 16, 16),
	"dpad": Rect2(0, 128, 16, 16),
}

# ---------- 字体 ----------

## 配置像素字体（关抗锯齿；字号请用 14 的整数倍保证像素对齐）
static func prepare_font() -> FontFile:
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font

## 创建 LabelSettings；outline_px<0 时按字号自动配描边
static func label_settings(size: int, color: Color = COL_CREAM, outline_px: int = -1) -> LabelSettings:
	var s: LabelSettings = LabelSettings.new()
	s.font = prepare_font()
	s.font_size = size
	s.font_color = color
	s.outline_size = (size / 7) if outline_px < 0 else outline_px
	s.outline_color = COL_OUTLINE
	return s

## 快捷创建 Label
static func make_label(text: String, size: int, color: Color = COL_CREAM, outline_px: int = -1) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.label_settings = label_settings(size, color, outline_px)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# ---------- 背景与根节点 ----------

## 创建全屏根 Control
static func full_rect_root() -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	return root

## 草地棋盘格背景（代码烘焙 8px 双色格，最近邻放大保持像素感）
static func make_grass_bg() -> TextureRect:
	var cell: int = 8
	var img: Image = Image.create(240, 135, false, Image.FORMAT_RGBA8)
	for y: int in 135:
		for x: int in 240:
			var even: bool = ((x / cell) + (y / cell)) % 2 == 0
			img.set_pixel(x, y, COL_GRASS_A if even else COL_GRASS_B)
	var rect: TextureRect = TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## 半透明遮罩（弹窗底）
static func make_dim_overlay(alpha: float = 0.45) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(0.09, 0.07, 0.05, alpha)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect

# ---------- 九宫格烘焙 ----------

## 从源贴图裁出区域，按 PATCH_SCALE 最近邻放大，保留像素阶梯圆角
static func _bake_patch(src: Texture2D, region: Rect2i) -> Texture2D:
	var img: Image = src.get_image()
	var crop: Image = img.get_region(region)
	crop.resize(region.size.x * PATCH_SCALE, region.size.y * PATCH_SCALE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(crop)

## 懒加载：放大后的面板 / 按钮 / 对话框贴图
static func _ensure_patches() -> void:
	if _tex_panel != null:
		return
	_tex_panel = _bake_patch(_tex_panel_src, PANEL_REGION_SRC)
	_tex_btn_normal = _bake_patch(_tex_btn_big_src, BTN_REGION_NORMAL_SRC)
	_tex_btn_pressed = _bake_patch(_tex_btn_big_src, BTN_REGION_PRESSED_SRC)
	_tex_btn_square = _bake_patch(_tex_btn_square_src, BTN_SQUARE_REGION_SRC)
	_tex_dialog = _bake_patch(_tex_dialog_src, DIALOG_REGION_SRC)

# ---------- 面板 ----------

## Sprout 空白圆角面板（九宫格拉伸；像素阶梯圆角）
static func make_panel(min_size: Vector2) -> NinePatchRect:
	_ensure_patches()
	var panel: NinePatchRect = NinePatchRect.new()
	panel.texture = _tex_panel
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m: int = PANEL_MARGIN_SRC * PATCH_SCALE
	panel.patch_margin_left = m
	panel.patch_margin_right = m
	panel.patch_margin_top = m
	panel.patch_margin_bottom = m
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

## Sprout 对话气泡（左侧带尾巴；适合教程提示）
static func make_dialog(min_size: Vector2) -> NinePatchRect:
	_ensure_patches()
	var bubble: NinePatchRect = NinePatchRect.new()
	bubble.texture = _tex_dialog
	bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bubble.patch_margin_left = DIALOG_MARGIN_L_SRC * PATCH_SCALE
	bubble.patch_margin_right = DIALOG_MARGIN_R_SRC * PATCH_SCALE
	bubble.patch_margin_top = DIALOG_MARGIN_T_SRC * PATCH_SCALE
	bubble.patch_margin_bottom = DIALOG_MARGIN_B_SRC * PATCH_SCALE
	bubble.custom_minimum_size = min_size
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bubble

# ---------- 按钮 ----------

## 用放大后的大按钮贴图构建 StyleBoxTexture（保留像素圆角）
static func _btn_stylebox(tex: Texture2D) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = float(BTN_MARGIN_L_SRC * PATCH_SCALE)
	style.texture_margin_right = float(BTN_MARGIN_R_SRC * PATCH_SCALE)
	style.texture_margin_top = float(BTN_MARGIN_T_SRC * PATCH_SCALE)
	style.texture_margin_bottom = float(BTN_MARGIN_B_SRC * PATCH_SCALE)
	# 内容边距按放大后的按钮厚度留白，文字不贴边
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 22.0
	return style

## Sprout 大按钮：像素字 + 常态/按下贴图 + 聚焦弹簧放大与橙色高亮。
## 鼠标悬停会自动抢焦点，保证键盘 / 手柄 / 鼠标三者状态一致。
static func make_big_button(text: String, font_px: int = 28, min_size: Vector2 = Vector2(384, 96)) -> Button:
	_ensure_patches()
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_ALL
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_stylebox_override("normal", _btn_stylebox(_tex_btn_normal))
	btn.add_theme_stylebox_override("hover", _btn_stylebox(_tex_btn_normal))
	btn.add_theme_stylebox_override("focus", _btn_stylebox(_tex_btn_normal))
	btn.add_theme_stylebox_override("pressed", _btn_stylebox(_tex_btn_pressed))
	btn.add_theme_stylebox_override("disabled", _btn_stylebox(_tex_btn_pressed))
	btn.add_theme_font_override("font", prepare_font())
	btn.add_theme_font_size_override("font_size", font_px)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	btn.add_theme_color_override("font_focus_color", COL_ACCENT)
	btn.add_theme_color_override("font_pressed_color", COL_INK)
	btn.add_theme_color_override("font_disabled_color", Color(COL_INK, 0.45))
	var spring: UiSpring = UiSpring.attach(btn, 0.4, 0.3)
	btn.focus_entered.connect(func() -> void: spring.set_scale_target(1.05))
	btn.focus_exited.connect(func() -> void: spring.set_scale_target(1.0))
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			btn.grab_focus()
	)
	return btn

## 方块勾选/图标按钮用的九宫格 StyleBox（像素圆角）
static func make_square_stylebox() -> StyleBoxTexture:
	_ensure_patches()
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = _tex_btn_square
	var m: float = float(6 * PATCH_SCALE)  # 源图圆角约 3～4px
	style.texture_margin_left = m
	style.texture_margin_right = m
	style.texture_margin_top = m
	style.texture_margin_bottom = m
	return style

# ---------- 图标 ----------

## 通用：从图集区域创建按整数倍放大的 TextureRect
static func _atlas_rect(tex: Texture2D, region: Rect2, px: float) -> TextureRect:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	var rect: TextureRect = TextureRect.new()
	rect.texture = atlas
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px * region.size.y / region.size.x)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## 键帽图标："W"~"Z" 单字母，或 "UP"/"LEFT"/"DOWN"/"RIGHT"/"ESC"/"DEL"
static func make_key_icon(key: String, px: float = 48.0) -> TextureRect:
	if SYMBOL_KEY_REGIONS.has(key):
		var region: Rect2 = SYMBOL_KEY_REGIONS[key] as Rect2
		return _atlas_rect(_tex_kb_symbols, region, px)
	var idx: int = key.unicode_at(0) - 65  # 'A'=65，字母表按行排列
	idx = clampi(idx, 0, 25)
	return _atlas_rect(_tex_kb_keys, Rect2(0, idx * 16, 16, 16), px)

## 手柄键图标："a" / "b" / "dpad"
static func make_pad_icon(name: String, px: float = 48.0) -> TextureRect:
	var region: Rect2 = PAD_REGIONS.get(name, PAD_REGIONS["a"]) as Rect2
	return _atlas_rect(_tex_pad, region, px)

## Sprout 图标：见 ICON_REGIONS 键名
static func make_icon(name: String, px: float = 48.0) -> TextureRect:
	var region: Rect2 = ICON_REGIONS.get(name, ICON_REGIONS["star_dark"]) as Rect2
	return _atlas_rect(_tex_icons, region, px)

## 红心贴图：state 0=满 1=半 2=空
static func heart_texture(state: int) -> AtlasTexture:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = _tex_hearts
	atlas.region = HEART_REGIONS[clampi(state, 0, 2)]
	return atlas

# ---------- 装饰 ----------

## 标题装饰用的猴子闲置动画（32x32 x18 帧）
static func make_monkey_sprite(sprite_scale: float = 5.0, flip: bool = false) -> AnimatedSprite2D:
	var tex: Texture2D = load("res://assets/characters/monkey_idle.png") as Texture2D
	var frames: SpriteFrames = SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 10.0)
	frames.set_animation_loop(&"idle", true)
	for i: int in 18:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * 32, 0, 32, 32)
		frames.add_frame(&"idle", atlas)
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = &"idle"
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.flip_h = flip
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.play()
	return sprite
