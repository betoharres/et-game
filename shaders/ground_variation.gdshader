shader_type spatial;

uniform vec3 grass_color : source_color = vec3(0.025, 0.105, 0.045);
uniform vec3 grass_light_color : source_color = vec3(0.045, 0.14, 0.065);
uniform vec3 soil_color : source_color = vec3(0.19, 0.085, 0.028);
uniform float patch_scale : hint_range(2.0, 24.0, 0.5) = 8.0;
uniform float soil_amount : hint_range(0.0, 1.0, 0.01) = 0.36;
uniform float color_variation : hint_range(0.0, 0.4, 0.01) = 0.12;


float hash21(vec2 point) {
	vec3 point3 = fract(vec3(point.xyx) * 0.1031);
	point3 += dot(point3, point3.yzx + 33.33);
	return fract((point3.x + point3.y) * point3.z);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


float layered_noise(vec2 point) {
	float result = value_noise(point) * 0.62;
	result += value_noise(point * 2.07 + vec2(4.2, 1.7)) * 0.28;
	result += value_noise(point * 4.13 + vec2(8.1, 3.4)) * 0.10;
	return result;
}


void fragment() {
	vec2 patch_uv = UV * patch_scale;
	float large_patches = layered_noise(patch_uv);
	float broken_edges = value_noise(patch_uv * 3.4 + vec2(2.7, 6.1));
	float soil_threshold = mix(0.68, 0.44, soil_amount);
	float soil_mask = smoothstep(
		soil_threshold - 0.05,
		soil_threshold + 0.04,
		large_patches * 0.82 + broken_edges * 0.18
	);

	float grass_mix = value_noise(UV * 56.0 + vec2(3.1, 9.4));
	vec3 grass = mix(grass_color, grass_light_color, grass_mix);
	float fine_variation = value_noise(UV * 145.0 + vec2(12.0, 5.0));
	grass *= mix(1.0 - color_variation, 1.0 + color_variation, fine_variation);

	float soil_variation = value_noise(UV * 82.0 + vec2(1.0, 17.0));
	vec3 soil = soil_color * mix(0.86, 1.12, soil_variation);
	ALBEDO = mix(grass, soil, soil_mask);
	ROUGHNESS = 0.96;
	SPECULAR = 0.18;
}
