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
## 世界提示与装饰性英文：保留 Sprout Lands 窄像素字体。
static var _font: FontFile = preload("res://assets/ui/pixel_font_sprout.ttf")
## 标题专用粗像素字体（Press Start 2P，SIL OFL 授权，8x8 网格设计）
static var _font_title: FontFile = preload("res://assets/ui/press_start_2p.ttf")
## 中文像素字体（IPix 12px）；中文正文与中文按钮统一从这里取字形。
static var _font_cjk: FontFile = preload("res://assets/ui/ipix_12px.ttf")
## 英文正文：高辨识度等宽字体，避免小字号继续使用装饰性像素字。
static var _font_body: FontFile = preload(
	"res://assets/ui/atkinson_hyperlegible_mono_regular.ttf"
)
## 编号、数值与虚拟键盘：粗体且默认使用斜线零，明确区分 0 / O / D。
static var _font_data: FontFile = preload(
	"res://assets/ui/atkinson_hyperlegible_mono_bold.ttf"
)
## 短英文操作按钮：用户提供的 Boxy Bold，仅用于非数据型展示文字。
static var _font_display: FontFile = preload("res://assets/ui/boxy_bold.ttf")
## 品牌副标题专用字重变体：中英文都用 IPix，并通过 embolden 增厚笔画。
static var _font_subtitle_bold: FontVariation = null
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
	"x": Rect2(0, 80, 16, 16),
	"dpad": Rect2(0, 128, 16, 16),
}

## 代码烘焙的按钮小图标：16x16 字符画（X = 实心像素）
## retry = 转圈箭头；levels = 三块关卡砖；next = 向右箭头
const PIXEL_ICONS: Dictionary = {
	"retry": [
		"................",
		"....XXXXXXX.....",
		"..XXXXXXXXXXX...",
		"..XXX....XXXXX..",
		".XXX....XXXXXX..",
		".XXX...XXXXXXXX.",
		".XX.....XXXXXX..",
		".XX......XXXX...",
		".XX.......XX....",
		".XX.............",
		".XXX............",
		".XXXX.......XX..",
		"..XXXXXXXXXXXX..",
		"....XXXXXXXX....",
		"................",
		"................",
	],
	"levels": [
		"................",
		".XXXXXX..XXXXXX.",
		".XXXXXX..XXXXXX.",
		".XXXXXX..XXXXXX.",
		".XXXXXX..XXXXXX.",
		".XXXXXX..XXXXXX.",
		".XXXXXX..XXXXXX.",
		"................",
		"................",
		"....XXXXXXXX....",
		"....XXXXXXXX....",
		"....XXXXXXXX....",
		"....XXXXXXXX....",
		"....XXXXXXXX....",
		"....XXXXXXXX....",
		"................",
	],
	"next": [
		"................",
		"................",
		".........X......",
		".........XX.....",
		".........XXX....",
		".........XXXX...",
		"..XXXXXXXXXXXX..",
		"..XXXXXXXXXXXXX.",
		"..XXXXXXXXXXXXX.",
		"..XXXXXXXXXXXX..",
		".........XXXX...",
		".........XXX....",
		".........XX.....",
		".........X......",
		"................",
		"................",
	],
	"home": [
		"................",
		".......XX.......",
		"......XXXX......",
		".....XXXXXX.....",
		"....XXXXXXXX....",
		"...XXXXXXXXXX...",
		"..XXXXXXXXXXXX..",
		".XXXXXXXXXXXXXX.",
		"...XXXXXXXXXX...",
		"...XX......XX...",
		"...XX......XX...",
		"...XX..XX..XX...",
		"...XX..XX..XX...",
		"...XXXXXXXXXX...",
		"................",
		"................",
	],
	"clear": [
		"................",
		".....XXXXXX.....",
		"....XXXXXXXX....",
		"...XXXXXXXXXX...",
		"...XX......XX...",
		"..XXXXXXXXXXXX..",
		"...XXXXXXXXXX...",
		"...XX.XX.XX.X...",
		"...XX.XX.XX.X...",
		"...XX.XX.XX.X...",
		"...XX.XX.XX.X...",
		"...XX.XX.XX.X...",
		"...XXXXXXXXXX...",
		"....XXXXXXXX....",
		"................",
		"................",
	],
}

# ---------- 字体 ----------

## 配置世界提示用像素字体（关抗锯齿；字号请用 14 的整数倍保证像素对齐）
static func prepare_font() -> FontFile:
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font

## 英文正文优先可读性；保留灰阶抗锯齿，避免非网格字号出现断笔。
static func prepare_body_font() -> FontFile:
	_font_body.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font_body.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return _font_body

## 数据专用粗体：等宽、斜线零，用于 ID、键盘和统计值。
static func prepare_data_font() -> FontFile:
	_font_data.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font_data.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return _font_data

## 短操作词专用展示字体；不可用于编号（其 0/O 轮廓相近）。
static func prepare_display_font() -> FontFile:
	_font_display.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font_display.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font_display

## 配置中文像素字体。
static func prepare_cjk_font() -> FontFile:
	_font_cjk.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font_cjk.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font_cjk

## 副标题专用粗体：避免细笔画被深色描边吞掉。
static func prepare_subtitle_font() -> FontVariation:
	if _font_subtitle_bold == null:
		_font_subtitle_bold = FontVariation.new()
		_font_subtitle_bold.base_font = prepare_cjk_font()
		_font_subtitle_bold.variation_embolden = 1.15
	return _font_subtitle_bold

## 判断文本是否包含中日韩统一表意文字。
static func _contains_cjk(text: String) -> bool:
	for index: int in text.length():
		var codepoint: int = text.unicode_at(index)
		if codepoint >= 0x3400 and codepoint <= 0x9FFF:
			return true
	return false

## 中文统一使用加粗 IPix；英文正文改用高辨识度 Atkinson。
static func _font_for_text(text: String, title: bool = false) -> Font:
	if _contains_cjk(text):
		return prepare_subtitle_font()
	return prepare_title_font() if title else prepare_body_font()

static func _world_font_for_text(text: String) -> Font:
	return prepare_subtitle_font() if _contains_cjk(text) else prepare_font()

static func _display_font_for_text(text: String) -> Font:
	return prepare_subtitle_font() if _contains_cjk(text) else prepare_display_font()

## 创建 LabelSettings；outline_px<0 时按字号自动配描边
static func label_settings(
	size: int,
	color: Color = COL_CREAM,
	outline_px: int = -1,
	text: String = "",
) -> LabelSettings:
	var s: LabelSettings = LabelSettings.new()
	s.font = _font_for_text(text)
	s.font_size = size
	s.font_color = color
	s.outline_size = (size / 7) if outline_px < 0 else outline_px
	s.outline_color = COL_OUTLINE
	return s

## 快捷创建 Label（默认奶油字 + 自动描边：适合草地 / 照片底）
static func make_label(text: String, size: int, color: Color = COL_CREAM, outline_px: int = -1) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.label_settings = label_settings(size, color, outline_px, text)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## 更新动态 Label 文本并同步切换中英文字体。
## 空文本创建的标签若直接写 .text，会继续使用拉丁字体并触发不一致的系统回退。
static func set_label_text(label: Label, text: String, title: bool = false) -> void:
	label.text = text
	if label.label_settings != null:
		label.label_settings.font = _font_for_text(text, title)

## 奶油面板上的正文：深棕墨色、零描边。
## 任务：在米色九宫格上保持最高可读性；描边会发脏，一律关掉。
static func make_panel_label(text: String, size: int = 28, alpha: float = 1.0) -> Label:
	return make_label(text, size, Color(COL_INK, alpha), 0)

## 副标题 / 次级说明：比正文小一档、墨色压到 0.55，零描边。
## 任务：交代附属信息（关名、限时、提示标签），绝不能和主标题抢权。
static func make_subtitle_label(text: String, size: int = 22) -> Label:
	var label: Label = make_panel_label(text, size, 0.55)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## 草地/照片/关卡世界上的次级字。
## 禁止使用 Godot outline_size；统一走连续像素扩张描边。
static func make_world_caption(text: String, size: int = 22) -> Control:
	return make_pixel_outline_text(text, size, Color(COL_CREAM, 0.92), 2)

## 场景背景上的任意文字：以方形核扩张深色字形，再叠加前景字面。
## 返回 Control；动态更新必须使用 set_pixel_outline_text/color。
## 会写入 custom_minimum_size，才能在 HBox/VBox 中按真实字宽排开，避免叠字。
static func make_pixel_outline_text(
	text: String,
	size: int,
	color: Color = COL_CREAM,
	outline_radius: int = 2,
) -> Control:
	var root: Control = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_settings: LabelSettings = _pixel_outline_settings(
		text, size, Color(COL_OUTLINE, 0.96)
	)
	var radius: int = maxi(1, outline_radius)
	root.set_meta("pixel_outline_radius", radius)
	root.set_meta("pixel_outline_font_size", size)
	for offset_y: int in range(-radius, radius + 1):
		for offset_x: int in range(-radius, radius + 1):
			if offset_x == 0 and offset_y == 0:
				continue
			root.add_child(_pixel_outline_layer(
				text,
				outline_settings,
				Vector2(float(offset_x), float(offset_y)),
				false,
			))
	var face_settings: LabelSettings = _pixel_outline_settings(text, size, color)
	root.add_child(_pixel_outline_layer(text, face_settings, Vector2.ZERO, true))
	_apply_pixel_outline_size(root, text, size, radius)
	return root

## 更新多层像素描边文字的内容。
static func set_pixel_outline_text(root: Control, text: String) -> void:
	for child: Node in root.get_children():
		var layer: Label = child as Label
		if layer != null:
			layer.text = text
	var font_size: int = int(root.get_meta("pixel_outline_font_size", 22))
	var radius: int = int(root.get_meta("pixel_outline_radius", 2))
	_apply_pixel_outline_size(root, text, font_size, radius)

## 按字形实测宽度给像素描边文字定最小尺寸，供容器布局使用。
static func _apply_pixel_outline_size(
	root: Control,
	text: String,
	font_size: int,
	outline_radius: int,
) -> void:
	var font: Font = _font_for_text(text)
	var measured: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var pad: float = float(maxi(1, outline_radius) * 2)
	root.custom_minimum_size = Vector2(
		ceili(measured.x + pad),
		ceili(maxf(measured.y, float(font_size)) + pad),
	)

## 更新多层像素描边文字的前景颜色，不改变深色外轮廓。
static func set_pixel_outline_color(root: Control, color: Color) -> void:
	var face: Label = root.get_node_or_null("Face") as Label
	if face != null:
		face.label_settings.font_color = color

## 标题 LOGO 下方的品牌副标题。
## 不使用 FontVariation 的 outline_size：关闭抗锯齿时它会在细笔画转角漏边。
## 这里以 3px 方形核扩张深色字形，再叠加奶油色前景，得到连续像素描边。
static func make_brand_subtitle(text: String, size: int = 44) -> Control:
	return make_pixel_outline_text(text, size, COL_CREAM, 3)

## 创建无描边、无阴影的世界文字字面设置。
static func _pixel_outline_settings(text: String, size: int, color: Color) -> LabelSettings:
	var settings: LabelSettings = LabelSettings.new()
	settings.font = _world_font_for_text(text)
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = 0
	settings.shadow_size = 0
	return settings

## 创建一层铺满父容器的字形，用偏移叠层形成像素描边。
static func _pixel_outline_layer(
	text: String,
	settings: LabelSettings,
	offset: Vector2,
	is_face: bool,
) -> Label:
	var label: Label = Label.new()
	if is_face:
		label.name = "Face"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = offset.x
	label.offset_bottom = offset.y
	label.text = text
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## 配置标题字体（Press Start 2P；关抗锯齿保持像素锐利）
## 该字体按 8x8 网格设计，字号请用 8 的倍数保证像素对齐
static func prepare_title_font() -> FontFile:
	_font_title.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font_title.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font_title

## 标题级粗像素字（Press Start 2P）。
## on_panel=true：面板内用实色 + 硬阴影（不用描边，避免奶油底发脏）；
## on_panel=false：草地/照片底用描边把字从背景里抠出来。
static func make_title_label(
	text: String,
	size: int = 48,
	color: Color = COL_CREAM,
	on_panel: bool = false,
) -> Label:
	var label: Label = Label.new()
	var s: LabelSettings = LabelSettings.new()
	s.font = _font_for_text(text, true)
	s.font_size = size
	s.font_color = color
	var font_px: int = maxi(2, size / 8)
	if on_panel:
		# 面板内：零描边 + 1 字体像素硬阴影，形成干净的抬升
		s.outline_size = 0
		s.shadow_size = font_px
		s.shadow_color = Color(COL_OUTLINE, 0.35)
		s.shadow_offset = Vector2(0, float(font_px))
	else:
		s.outline_size = font_px
		s.outline_color = COL_OUTLINE
		s.shadow_size = 0
	label.text = text
	label.label_settings = s
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	btn.add_theme_font_override("font", _display_font_for_text(text))
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

## 编号网格与枚举行使用的紧凑按钮；橙色边框让键盘/手柄焦点始终可见。
static func make_compact_button(text: String, min_size: Vector2 = Vector2(160, 58)) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", _font_for_text(text))
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", COL_INK)
	button.add_theme_color_override("font_hover_color", COL_ACCENT)
	button.add_theme_color_override("font_focus_color", COL_ACCENT)

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(COL_CREAM, 0.96)
	normal.border_color = Color(COL_OUTLINE, 0.55)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)

	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.border_color = COL_ACCENT
	focus.set_border_width_all(6)
	button.add_theme_stylebox_override("focus", focus)

	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("eed7a8")
	button.add_theme_stylebox_override("pressed", pressed)
	var spring: UiSpring = UiSpring.attach(button, 0.35, 0.3)
	button.focus_entered.connect(func() -> void: spring.set_scale_target(1.06))
	button.focus_exited.connect(func() -> void: spring.set_scale_target(1.0))
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			button.grab_focus()
	)
	return button

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

## 键帽图标：图集内特殊键或单字母；ENTER 等长键使用代码绘制键帽。
static func make_key_icon(key: String, px: float = 48.0) -> Control:
	if SYMBOL_KEY_REGIONS.has(key):
		var region: Rect2 = SYMBOL_KEY_REGIONS[key] as Rect2
		return _atlas_rect(_tex_kb_symbols, region, px)
	if key.length() != 1:
		return _make_text_key_icon(key, px)
	var idx: int = key.unicode_at(0) - 65  # 'A'=65，字母表按行排列
	idx = clampi(idx, 0, 25)
	return _atlas_rect(_tex_kb_keys, Rect2(0, idx * 16, 16, 16), px)

## 为图集中不存在的长键绘制统一像素键帽。
static func _make_text_key_icon(key: String, px: float) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(px * 1.9, px)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COL_CREAM
	style.border_color = COL_OUTLINE
	style.set_border_width_all(maxi(2, int(px / 12.0)))
	style.set_corner_radius_all(maxi(3, int(px / 10.0)))
	panel.add_theme_stylebox_override("panel", style)
	var label: Label = make_panel_label(key, maxi(12, int(px * 0.34)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

## 手柄键图标："a" / "b" / "dpad"
static func make_pad_icon(name: String, px: float = 48.0) -> TextureRect:
	var region: Rect2 = PAD_REGIONS.get(name, PAD_REGIONS["a"]) as Rect2
	return _atlas_rect(_tex_pad, region, px)

## 按当前设备组合生成一行操作提示。
## 纯键盘/纯手柄只显示对应图标；混合输入使用“/”明确分隔两组图标。
static func make_device_hint_row(
	key_names: Array[String],
	pad_names: Array[String],
	caption: String,
	px: float = 44.0,
	profile: InputHub.SessionProfile = InputHub.SessionProfile.UNKNOWN,
) -> HBoxContainer:
	var resolved: InputHub.SessionProfile = profile
	if resolved == InputHub.SessionProfile.UNKNOWN:
		resolved = InputHub.menu_profile()
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var show_keyboard: bool = resolved in [
		InputHub.SessionProfile.KEYBOARD_ONLY,
		InputHub.SessionProfile.MIXED,
	]
	var show_gamepad: bool = resolved in [
		InputHub.SessionProfile.GAMEPAD_ONLY,
		InputHub.SessionProfile.MIXED,
	]
	if show_keyboard:
		for key_name: String in key_names:
			row.add_child(make_key_icon(key_name, px))
	if show_keyboard and show_gamepad:
		row.add_child(make_world_caption("/", maxi(22, int(px * 0.62))))
	if show_gamepad:
		for pad_name: String in pad_names:
			row.add_child(make_pad_icon(pad_name, px))
	if caption != "":
		row.add_child(make_world_caption(caption, maxi(20, int(px * 0.56))))
	return row

## 烘焙 PIXEL_ICONS 中的像素图标：按整数倍最近邻放大，颜色可定制
static func make_button_icon(icon_name: String, icon_scale: int = 2, color: Color = COL_INK) -> Texture2D:
	var rows: Array = PIXEL_ICONS.get(icon_name, []) as Array
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in mini(16, rows.size()):
		var row: String = str(rows[y])
		for x: int in mini(16, row.length()):
			if row[x] == "X":
				img.set_pixel(x, y, color)
	img.resize(16 * icon_scale, 16 * icon_scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

## 返回可直接用于 Button.icon 的等倍像素图标纹理。
static func make_ui_icon_texture(name: String, icon_scale: int = 2) -> Texture2D:
	var region: Rect2 = ICON_REGIONS.get(name, ICON_REGIONS["star_dark"]) as Rect2
	var image: Image = _tex_icons.get_image().get_region(Rect2i(region))
	image.resize(
		int(region.size.x) * icon_scale,
		int(region.size.y) * icon_scale,
		Image.INTERPOLATE_NEAREST,
	)
	return ImageTexture.create_from_image(image)

## Sprout 图标：见 ICON_REGIONS 键名
static func make_icon(name: String, px: float = 48.0) -> TextureRect:
	var region: Rect2 = ICON_REGIONS.get(name, ICON_REGIONS["star_dark"]) as Rect2
	return _atlas_rect(_tex_icons, region, px)

## 结算星星贴图缓存（键："earned_frames" / "empty"，首次使用时烘焙）
static var _star_tex_cache: Dictionary = {}

## 闪光扫过动画的对角线阈值（x+y 落在 [阈值, 阈值+2) 的像素被点亮）
const STAR_SHINE_BANDS: Array[int] = [7, 11, 15, 19]
## 扫光每帧时长（秒）
const STAR_SHINE_FRAME_S: float = 0.07

## 结算界面像素金星：以图集 star_cream 的 alpha 为掩膜逐像素烘焙。
## 描边 / 三段色带 / 高光全部落在 16x16 像素网格上。
## earned 星带「闪光扫过」帧动画：长停顿后一道斜向高光快速掠过；
## hold_s 控制停顿时长，三颗星传不同值可错开闪光节奏。
static func make_pixel_star(earned: bool, px: float = 96.0, hold_s: float = 1.2) -> TextureRect:
	if not _star_tex_cache.has("earned_frames"):
		var frames: Array[Texture2D] = [_bake_star_texture(true, -1)]
		for band: int in STAR_SHINE_BANDS:
			frames.append(_bake_star_texture(true, band))
		_star_tex_cache["earned_frames"] = frames
		_star_tex_cache["empty"] = _bake_star_texture(false, -1)

	var rect: TextureRect = TextureRect.new()
	# 注意：GDScript 的 as 不支持带元素类型的数组，这里用无类型 Array 取帧
	var frames: Array = _star_tex_cache["earned_frames"] as Array
	if earned:
		rect.texture = frames[0] as Texture2D
	else:
		rect.texture = _star_tex_cache["empty"] as Texture2D
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if earned:
		# Timer 驱动帧循环：帧 0 停 hold_s，其余扫光帧快速播放
		var state: Dictionary = {"frame": 0}
		var timer: Timer = Timer.new()
		timer.one_shot = true
		timer.autostart = true
		timer.wait_time = hold_s
		rect.add_child(timer)
		timer.timeout.connect(func() -> void:
			state["frame"] = (int(state["frame"]) + 1) % frames.size()
			rect.texture = frames[int(state["frame"])] as Texture2D
			timer.start(hold_s if int(state["frame"]) == 0 else STAR_SHINE_FRAME_S)
		)
	return rect

## 逐像素烘焙星星：earned=金色三段色带+高光；否则为半透明的凹陷空槽。
## shine_band >= 0 时，把 x+y 落在 [shine_band, shine_band+2) 的实心像素
## 点亮成近白，形成斜向扫光帧。
static func _bake_star_texture(earned: bool, shine_band: int = -1) -> Texture2D:
	# 用图集里奶油星的 alpha 通道当星形掩膜（16x16）
	var region: Rect2 = ICON_REGIONS["star_cream"] as Rect2
	var src: Image = _tex_icons.get_image().get_region(Rect2i(region))
	var mask: Array[bool] = []
	mask.resize(16 * 16)
	for my: int in 16:
		for mx: int in 16:
			mask[my * 16 + mx] = src.get_pixel(mx, my).a > 0.5

	# 配色：金星三段色带 / 空槽为压暗的凹陷色
	var col_hi: Color = Color("ffdf6e")      # 顶部亮金
	var col_mid: Color = Color("f2a93b")     # 中段主金
	var col_lo: Color = Color("d97e22")      # 底部暗金
	var col_spark: Color = Color("fff6d8")   # 顶端高光
	var col_outline: Color = COL_OUTLINE
	if not earned:
		col_hi = Color(0.42, 0.32, 0.23, 0.5)
		col_mid = col_hi
		col_lo = Color(0.36, 0.27, 0.19, 0.5)
		col_spark = col_hi
		col_outline = Color(COL_OUTLINE, 0.55)

	var col_shine: Color = Color("fffbe8")  # 扫光帧的点亮色
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for py: int in 16:
		for px_i: int in 16:
			if _mask_solid(mask, px_i, py):
				var c: Color = col_mid
				if py <= 3:
					c = col_spark  # 顶端尖角打高光
				elif py <= 6:
					c = col_hi
				elif py >= 10:
					c = col_lo
				# 斜向扫光带：覆盖在色带之上
				if shine_band >= 0 and (px_i + py) >= shine_band and (px_i + py) < shine_band + 2:
					c = col_shine
				img.set_pixel(px_i, py, c)
			else:
				# 8 邻域内有实心像素则画 1px 描边
				var edge: bool = false
				for oy: int in range(-1, 2):
					for ox: int in range(-1, 2):
						if _mask_solid(mask, px_i + ox, py + oy):
							edge = true
				if edge:
					img.set_pixel(px_i, py, col_outline)

	img.resize(16 * 8, 16 * 8, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

## 掩膜内是否为实心像素（越界视为空，供描边膨胀使用）
static func _mask_solid(mask: Array[bool], ix: int, iy: int) -> bool:
	return ix >= 0 and ix < 16 and iy >= 0 and iy < 16 and mask[iy * 16 + ix]

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
