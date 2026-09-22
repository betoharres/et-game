shader_type spatial;

render_mode unshaded, cull_disabled;

uniform sampler2D text_texture : source_color;
uniform vec4 ink_color : source_color = vec4(0.025, 0.022, 0.018, 1.0);
uniform float near_distance = 3.0;
uniform float far_distance = 12.0;
uniform float ring_thickness = 0.035;
uniform float ink_irregularity = 0.18;
uniform float morph_progress = 0.0;
uniform float animation_speed = 0.65;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float ink_ring(vec2 p, float radius, float thickness, float wobble, float time_value, float seed) {
	float angle = atan(p.y, p.x);
	vec2 direction = vec2(cos(angle), sin(angle));
	float n = noise(direction * 2.0 + vec2(time_value * 0.35 + seed, -time_value * 0.21));
	float distorted_radius = radius + (n - 0.5) * wobble;
	float thickness_noise = noise(direction * 3.5 + vec2(seed * 2.0, time_value * 0.12));
	float variable_thickness = thickness * (0.62 + thickness_noise * 1.45);
	float stroke = 1.0 - smoothstep(variable_thickness, variable_thickness + 0.012, abs(length(p) - distorted_radius));

	float broken_arc = noise(direction * 1.65 + vec2(seed, -time_value * 0.08));
	float coverage = smoothstep(0.20, 0.34, broken_arc);
	float gap_angle = seed * 4.7 - 1.2;
	float gap_distance = abs(atan(sin(angle - gap_angle), cos(angle - gap_angle)));
	float intentional_gap = smoothstep(0.035, 0.16, gap_distance);
	return stroke * coverage * intentional_gap;
}

float ink_blob(vec2 p, vec2 center, float radius, float time_value) {
	vec2 q = p - center;
	float distorted = radius + (noise(q * 7.0 + vec2(-time_value * 0.27, time_value * 0.19)) - 0.5) * ink_irregularity;
	return 1.0 - smoothstep(distorted, distorted + 0.02, length(q));
}

float alien_writing(vec2 uv, float morph, float time_value) {
	vec2 p = uv - 0.5;
	p.x *= 1.45;

	float displacement = (1.0 - morph) * 0.045;
	p += vec2(
		noise(uv * 6.0 + vec2(time_value * 0.4, 0.0)) - 0.5,
		noise(uv * 6.0 + vec2(0.0, -time_value * 0.35)) - 0.5
	) * displacement;

	float pulse = sin(time_value * 2.0 + p.x * 5.0) * 0.012 * (1.0 - morph);
	float ink = ink_ring(p, 0.27 + pulse, ring_thickness, 0.055, time_value, 0.35);
	ink = max(ink, ink_ring(p - vec2(0.18, 0.02), 0.12, ring_thickness * 0.7, 0.04, time_value * 1.2, 1.7));
	ink = max(ink, ink_blob(p, vec2(-0.22, 0.12), 0.055 + pulse, time_value));
	ink = max(ink, ink_blob(p, vec2(0.08, -0.18), 0.035, time_value * 1.4));
	ink = max(ink, ink_blob(p, vec2(-0.08, 0.25), 0.026, time_value * 0.8));
	ink = max(ink, ink_blob(p, vec2(0.24, 0.04), 0.022, time_value * 1.1));
	ink = max(ink, ink_blob(p, vec2(-0.27, -0.10), 0.018, time_value * 1.3));

	float angle = atan(p.y, p.x);
	float spokes = smoothstep(0.025, 0.0, abs(sin(angle * 7.0)));
	spokes *= smoothstep(0.40, 0.05, length(p)) * 0.35;
	return max(ink, spokes);
}

void fragment() {
	float morph = clamp(morph_progress, 0.0, 1.0);
	float time_value = TIME * animation_speed;
	float edge_noise = noise(UV * 18.0 + vec2(time_value * 0.16, -time_value * 0.11));
	float alien = alien_writing(UV, morph, time_value) * smoothstep(0.25, 0.65, edge_noise);
	float text_alpha = texture(text_texture, UV).a;

	float dissolve_noise = noise(UV * 11.0 + vec2(-time_value * 0.22, time_value * 0.18));
	float transition_field = morph + (dissolve_noise - 0.5) * 0.34;
	float text_reveal = smoothstep(0.08, 0.92, transition_field);
	float ink_survival = 1.0 - smoothstep(0.08, 0.90, morph + (edge_noise - 0.5) * 0.18);
	float temporary_ink = text_alpha * (1.0 - text_reveal) * dissolve_noise * 0.45;
	float alpha = max(alien * ink_survival, text_alpha * text_reveal + temporary_ink);
	alpha *= 0.85 + edge_noise * 0.25;

	ALBEDO = ink_color.rgb;
	ALPHA = alpha * ink_color.a;
}
