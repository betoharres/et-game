shader_type spatial;

render_mode unshaded, cull_disabled;

uniform sampler2D circle_texture : source_color;
uniform vec4 ink_color : source_color = vec4(0.025, 0.022, 0.018, 1.0);
uniform float morph_progress: hint_range(0.0, 1.0) = 0.0;

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

void fragment() {
	float time_value = TIME * 0.45;
	vec2 centered_uv = UV - 0.5;
	float animated_amount = mix(0.008, 0.075, morph_progress);
	vec2 distortion = vec2(
		noise(centered_uv * 5.0 + vec2(time_value, 0.0)) - 0.5,
		noise(centered_uv * 5.0 + vec2(0.0, -time_value * 0.8)) - 0.5
	) * animated_amount;

	vec2 warped_uv = centered_uv + distortion + centered_uv * morph_progress * 0.08;
	float alpha = texture(circle_texture, warped_uv + 0.5).a;
	float secondary_alpha = texture(circle_texture, warped_uv + vec2(0.012, -0.008) * morph_progress + 0.5).a;
	alpha = max(alpha, secondary_alpha * morph_progress * 0.45);
	alpha *= 1.0 - smoothstep(0.72, 1.0, morph_progress);

	ALBEDO = ink_color.rgb;
	ALPHA = alpha * ink_color.a;
}
