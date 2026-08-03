shader_type canvas_item;
// 暖白闪：flash→1 时混向略带奶油的暖白，而不是冷纯白（传送更高级）。
// 保留 COLOR modulate，淡出仍生效。

uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// 二次曲线：前半段慢抬，后半段才顶满，避免瞬间漂白
	float t = flash * flash;
	base.rgb = mix(base.rgb, vec3(1.0, 0.97, 0.88), t * 0.92);
	COLOR = base * COLOR;
}
