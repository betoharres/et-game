shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.025, 0.05, 0.14);
uniform vec3 horizon_color : source_color = vec3(0.04, 0.08, 0.18);
uniform vec3 lower_sky_color : source_color = vec3(0.012, 0.02, 0.05);
uniform float star_density : hint_range(0.0, 1.0, 0.01) = 0.56;
uniform float star_brightness : hint_range(0.0, 3.0, 0.01) = 1.15;
uniform float twinkle_speed : hint_range(0.0, 3.0, 0.01) = 0.42;
uniform float twinkle_amount : hint_range(0.0, 0.5, 0.01) = 0.16;
uniform float star_seed = 73021.0;
uniform vec3 moon_direction = vec3(0.48, 0.34, 0.81);
uniform vec3 moon_color : source_color = vec3(0.72, 0.82, 1.0);
uniform float moon_angular_size : hint_range(0.01, 0.12, 0.001) = 0.028;
uniform float moon_brightness : hint_range(0.0, 6.0, 0.05) = 2.4;
uniform float moon_halo_strength : hint_range(0.0, 2.0, 0.01) = 0.48;
uniform float cloud_speed : hint_range(0.0, 0.1, 0.001) = 0.008;
uniform float cloud_opacity : hint_range(0.0, 0.5, 0.01) = 0.11;


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


vec3 procedural_stars(vec3 direction, vec2 sky_uv) {
	vec2 grid = sky_uv * vec2(520.0, 260.0);
	vec2 cell = floor(grid) + vec2(star_seed * 0.013, star_seed * 0.031);
	vec2 local = fract(grid) - 0.5;
	float existence = hash21(cell + 17.0);
	float star = step(1.0 - star_density * 0.026, existence);
	float size_roll = hash21(cell + 93.0);
	float large_star = step(0.90, size_roll);
	float radius = mix(0.11, 0.27, large_star);
	float core = 1.0 - smoothstep(radius * 0.35, radius, length(local));

	float tint_roll = hash21(cell + 151.0);
	vec3 warm_tint = vec3(1.0, 0.88, 0.72);
	vec3 cold_tint = vec3(0.62, 0.80, 1.0);
	vec3 star_tint = mix(warm_tint, cold_tint, smoothstep(0.18, 0.82, tint_roll));

	float can_twinkle = step(0.88, hash21(cell + 221.0));
	float phase = hash21(cell + 307.0) * TAU;
	float speed_variation = mix(0.35, 1.0, hash21(cell + 401.0));
	float pulse = sin(TIME * twinkle_speed * speed_variation + phase);
	float twinkle = 1.0 + can_twinkle * pulse * twinkle_amount;
	float horizon_fade = smoothstep(0.015, 0.30, direction.y);
	float intensity = mix(0.42, 1.0, large_star);
	return star_tint * star * core * star_brightness * twinkle * intensity * horizon_fade;
}


vec3 procedural_moon(vec3 direction) {
	vec3 moon_dir = normalize(moon_direction);
	float moon_angle = acos(clamp(dot(direction, moon_dir), -1.0, 1.0));
	float disc = 1.0 - smoothstep(moon_angular_size * 0.91, moon_angular_size, moon_angle);
	float halo = exp(-moon_angle * 42.0) * moon_halo_strength;

	vec3 reference = abs(moon_dir.y) > 0.96 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 moon_right = normalize(cross(reference, moon_dir));
	vec3 moon_up = normalize(cross(moon_dir, moon_right));
	vec2 moon_uv = vec2(dot(direction, moon_right), dot(direction, moon_up)) / max(moon_angular_size, 0.001);
	float crater_a = 1.0 - smoothstep(0.12, 0.23, length(moon_uv - vec2(-0.25, 0.18)));
	float crater_b = 1.0 - smoothstep(0.08, 0.17, length(moon_uv - vec2(0.27, -0.16)));
	float crater_c = 1.0 - smoothstep(0.06, 0.13, length(moon_uv - vec2(0.05, 0.32)));
	float crater_shade = 1.0 - (crater_a * 0.15 + crater_b * 0.11 + crater_c * 0.08);
	return moon_color * (disc * moon_brightness * crater_shade + halo);
}


void sky() {
	if (AT_CUBEMAP_PASS) {
		// The animated details do not need to enter ambient lighting/reflections.
		COLOR = vec3(0.007, 0.012, 0.03);
	} else {
		vec3 direction = normalize(EYEDIR);
		float upper_mix = pow(clamp(direction.y * 0.82 + 0.18, 0.0, 1.0), 0.58);
		vec3 background = mix(horizon_color, zenith_color, upper_mix);
		background = mix(lower_sky_color, background, smoothstep(-0.20, 0.08, direction.y));

		vec2 cloud_uv = SKY_COORDS * vec2(8.0, 3.2);
		cloud_uv.x += TIME * cloud_speed;
		float cloud_a = value_noise(cloud_uv);
		float cloud_b = value_noise(cloud_uv * 2.07 + vec2(4.3, 1.7));
		float clouds = smoothstep(0.58, 0.82, cloud_a * 0.68 + cloud_b * 0.32);
		clouds *= smoothstep(0.02, 0.30, direction.y) * (1.0 - smoothstep(0.62, 0.90, direction.y));
		background *= 1.0 - clouds * cloud_opacity;

		vec3 stars = procedural_stars(direction, SKY_COORDS) * (1.0 - clouds * 0.55);
		vec3 moon = procedural_moon(direction) * (1.0 - clouds * 0.32);
		COLOR = background + stars + moon;
	}
}
