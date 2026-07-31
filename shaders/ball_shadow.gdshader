shader_type canvas_item;

// ============================================================
// 球的落地阴影：一个像素化的半透明椭圆
// （椭圆压扁效果由节点的 scale 完成，这里只画量化的圆盘）
// ============================================================

// 虚拟像素数，与球贴图保持一致
uniform float pixel_count : hint_range(8.0, 128.0) = 40.0;
// 阴影颜色（半透明深色）
uniform vec4 shadow_color : source_color = vec4(0.16, 0.15, 0.10, 0.35);

void fragment() {
	// UV 量化，保证阴影边缘也是像素锯齿风格
	vec2 uv = (floor(UV * pixel_count) + 0.5) / pixel_count;
	vec2 p = uv * 2.0 - 1.0;
	COLOR = dot(p, p) <= 1.0 ? shadow_color : vec4(0.0);
}
