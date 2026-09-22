shader_type spatial;

render_mode unshaded, cull_disabled;

uniform sampler2D text_texture : source_color;
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
	float time_value = TIME * 0.8;
	vec2 centered_uv = UV - 0.5;
	float distortion_amount = (1.0 - morph_progress) * 0.10;
	vec2 distortion = vec2(
		noise(centered_uv * 7.0 + vec2(time_value, 0.0)) - 0.5,
		noise(centered_uv * 7.0 + vec2(0.0, -time_value)) - 0.5
	) * distortion_amount;

	vec2 warped_uv = centered_uv + distortion;
	float text_alpha = texture(text_texture, warped_uv + 0.5).a;
	float ink_edge = 0.88 + noise(UV * 18.0 + time_value) * 0.18;

	ALBEDO = ink_color.rgb;
	ALPHA = text_alpha * morph_progress * ink_edge * ink_color.a;
}
