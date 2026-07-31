shader_type canvas_item;
render_mode blend_mix, unshaded;

// ============================================================
// 像素风暗角：径向渐变 + UV 量化 + 透明度阶梯
// 叠在分屏半屏上，只压暗四角，中间几乎不动
// ============================================================

/// 暗角最大不透明度（整体很轻，只在嘴角一点点）
uniform float intensity : hint_range(0.0, 1.0) = 0.32;
/// 开始变暗的内半径（相对半屏 UV，椭圆空间）
uniform float inner_radius : hint_range(0.0, 1.5) = 0.48;
/// 最暗处的外半径
uniform float outer_radius : hint_range(0.0, 2.0) = 1.18;
/// 虚拟像素网格密度（越大颗粒越细）
uniform float pixel_count : hint_range(8.0, 128.0) = 36.0;
/// 渐变阶梯数（像素风分层，不要太碎）
uniform float steps : hint_range(2.0, 12.0) = 5.0;
/// X 方向拉伸：半屏偏瘦时让暗角更贴四角而不是左右侧
uniform float aspect_bias : hint_range(0.5, 2.0) = 1.4;
/// 暗角颜色（偏暖棕黑，贴合 Sprout 调色）
uniform vec4 vignette_color : source_color = vec4(0.04, 0.03, 0.025, 1.0);

void fragment() {
	// UV 量化成像素块，边缘呈锯齿状而非光滑羽化
	vec2 uv = (floor(UV * pixel_count) + 0.5) / pixel_count;
	vec2 p = uv * 2.0 - 1.0;
	p.x *= aspect_bias;
	float dist = length(p);

	// 平滑径向权重，再量化成阶梯透明度
	float t = smoothstep(inner_radius, outer_radius, dist);
	t = floor(t * steps + 0.001) / steps;
	float alpha = t * intensity;

	COLOR = vec4(vignette_color.rgb, alpha);
}
