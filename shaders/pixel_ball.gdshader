shader_type canvas_item;

// ============================================================
// 伪 3D 像素球着色器
// 思路：把 2D 圆盘上的每个（量化后的）像素反推成球面法线，
// 再用脚本传入的姿态矩阵把法线旋转到球的局部坐标系里采样
// 球面图案（经度条纹 + 极帽 + 斑点），最后叠加色阶化光照。
// 这样球滚动时贴图会跟着姿态一起转，产生真实的 3D 滚动感。
// ============================================================

// 球体虚拟像素数（应等于贴图边长，保证像素颗粒和世界像素对齐）
uniform float pixel_count : hint_range(8.0, 128.0) = 40.0;
// 球姿态旋转矩阵（局部 -> 视图空间），由 ball.gd 每帧传入
uniform mat3 ball_rot;
// 指向光源的方向（视图空间，y 轴向下，z 轴指向相机）
uniform vec3 light_dir = vec3(-0.45, -0.55, 0.70);
// 受击闪红强度（0~1，由 BallHealth 驱动）
	uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
	// 重生闪白（Celeste / 平台机经典受击无敌闪）
	uniform float spawn_flash : hint_range(0.0, 1.0) = 0.0;

// —— Sprout Lands 风格配色 ——
uniform vec4 color_cream : source_color = vec4(0.949, 0.898, 0.737, 1.0);   // 奶油色条纹
uniform vec4 color_green : source_color = vec4(0.475, 0.671, 0.298, 1.0);   // 草绿条纹
uniform vec4 color_coral : source_color = vec4(0.871, 0.545, 0.451, 1.0);   // 珊瑚色条纹
uniform vec4 color_cap : source_color = vec4(0.573, 0.416, 0.298, 1.0);     // 两极的棕色小帽
uniform vec4 color_outline : source_color = vec4(0.271, 0.322, 0.196, 1.0); // 深色描边

// 简单二维哈希，用来在球面上撒杂色斑点（噪声让滚动更容易被看出来）
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	// 1) UV 量化 -> 像素化（所有后续计算都基于量化后的坐标）
	vec2 uv = (floor(UV * pixel_count) + 0.5) / pixel_count;
	vec2 p = uv * 2.0 - 1.0; // 圆盘坐标，范围 [-1, 1]
	float r2 = dot(p, p);

	if (r2 > 1.0) {
		// 圆外完全透明
		COLOR = vec4(0.0);
	} else {
		// 2) 由圆盘位置反推球面法线（视图空间，z 朝向相机）
		float z = sqrt(1.0 - r2);
		vec3 n = vec3(p, z);

		// 3) 逆旋转到球的局部坐标，得到"粘"在球面上的稳定纹理方向
		vec3 ln = transpose(ball_rot) * n;
		float lon = atan(ln.x, ln.z);                 // 经度 (-PI, PI]
		float lat = asin(clamp(ln.y, -1.0, 1.0));     // 纬度 [-PI/2, PI/2]

		// 4) 球面图案：六瓣经度条纹 + 两极小帽
		vec3 base;
		if (abs(lat) > 1.28) {
			base = color_cap.rgb;
		} else {
			int seg = int(floor(mod(lon / TAU * 6.0 + 12.0, 6.0)));
			if (seg == 1 || seg == 5) {
				base = color_green.rgb;
			} else if (seg == 3) {
				base = color_coral.rgb;
			} else {
				base = color_cream.rgb;
			}
		}
		// 斑点噪声：稀疏地压暗一些"格子"，增强滚动的视觉反馈
		float speck = hash21(floor(vec2(lon * 5.0, lat * 5.0)));
		if (speck > 0.82) {
			base *= 0.88;
		}

		// 5) 色阶化光照（4 档），营造像素风的立体体积感
		vec3 l = normalize(light_dir);
		float d = clamp(dot(n, l), -1.0, 1.0) * 0.5 + 0.5;
		float shade;
		if (d > 0.80) {
			shade = 1.08;
		} else if (d > 0.58) {
			shade = 0.95;
		} else if (d > 0.34) {
			shade = 0.78;
		} else {
			shade = 0.60;
		}
		vec3 col = base * shade;

		// 6) 小面积镜面高光（靠近光源方向的一小块提亮）
		vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
		if (dot(n, h) > 0.982) {
			col = mix(col, vec3(1.0), 0.75);
		}

		// 7) 外圈深色描边，贴合像素美术风格
		if (r2 > 1.0 - 3.0 / pixel_count) {
			col = color_outline.rgb;
		}

		// 8) 受击闪红
		if (damage_flash > 0.001) {
			col = mix(col, vec3(0.92, 0.28, 0.22), damage_flash * 0.65);
		}
		// 9) 重生闪白
		if (spawn_flash > 0.001) {
			col = mix(col, vec3(1.0, 1.0, 1.0), spawn_flash * 0.85);
		}

		COLOR = vec4(col, 1.0);
	}
}
