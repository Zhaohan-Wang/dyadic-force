shader_type canvas_item;
render_mode blend_mix, unshaded;

// ============================================================
// 分屏中缝的像素阶梯侧影：从透明过渡到半透明深色
// UV.x = 0 靠近画面外/透明侧，UV.x = 1 靠近分割线
// ============================================================

uniform float intensity : hint_range(0.0, 1.0) = 0.18;
uniform float pixel_count : hint_range(4.0, 64.0) = 16.0;
uniform float steps : hint_range(2.0, 10.0) = 4.0;
/// 为 true 时从右向左加深（右半屏贴分割线用）
uniform bool flip_x = false;
uniform vec4 fade_color : source_color = vec4(0.07, 0.06, 0.05, 1.0);

void fragment() {
	float u = flip_x ? (1.0 - UV.x) : UV.x;
	float x = (floor(u * pixel_count) + 0.5) / pixel_count;
	float t = floor(x * steps + 0.001) / steps;
	COLOR = vec4(fade_color.rgb, t * intensity);
}
