shader_type canvas_item;
// 传送门漩涡：相位由脚本累加；圆画在贴图内侧（留边）。
// 空闲偏透（地面贴花），靠近/充能才抬不透明度——让"有反应"本身成为反馈。

uniform float proximity : hint_range(0.0, 1.0) = 0.0;
uniform float activation : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.0;
uniform float pulse_phase = 0.0;
uniform float fit : hint_range(0.5, 1.0) = 0.82;

const vec3 COL_DEEP = vec3(0.09, 0.13, 0.30);
const vec3 COL_SWIRL = vec3(0.22, 0.55, 0.74);
const vec3 COL_BRIGHT = vec3(0.62, 0.95, 0.97);
const vec3 COL_WHITE = vec3(1.0, 0.99, 0.94);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0 / max(fit, 0.01);
	float ang = atan(d.y, d.x);

	float swirl = ang + spin - r * 5.5;
	float arm = 0.5 + 0.5 * sin(swirl * 3.0);
	arm = floor(arm * 3.0 + 0.001) / 3.0;

	vec3 col = mix(COL_DEEP, COL_SWIRL, arm);

	float core = floor(clamp(1.0 - r * 2.2, 0.0, 1.0) * 3.0) / 3.0;
	col = mix(col, COL_BRIGHT, core * (0.28 + proximity * 0.55));

	float rim = step(0.80, r) * step(r, 1.0);
	float pulse = 0.5 + 0.5 * sin(pulse_phase);
	col = mix(col, COL_BRIGHT, rim * (0.25 * pulse + 0.45 * proximity));

	col += vec3(0.08, 0.10, 0.11) * proximity;

	// 充能只点亮门心与外缘，绝不把整个椭圆填成白盘。
	// 漩涡纹理必须始终可见，玩家才能读到“正在旋转/吸入”。
	float hot_core = smoothstep(0.46, 0.0, r) * activation * 0.78;
	float hot_rim = rim * activation * 0.42;
	col = mix(col, COL_WHITE, clamp(hot_core + hot_rim, 0.0, 0.86));

	// 空闲 ~0.55（贴地可读但不抢球）；靠近/充能抬到接近实色
	float alpha = step(r, 1.0) * (0.55 + 0.30 * proximity + 0.15 * activation);
	COLOR = vec4(col, alpha);
}
