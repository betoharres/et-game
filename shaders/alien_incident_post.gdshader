shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float grain_amount : hint_range(0.0, 0.08, 0.001) = 0.024;
uniform float vignette_amount : hint_range(0.0, 0.5, 0.01) = 0.20;
uniform float chromatic_aberration : hint_range(0.0, 0.004, 0.0001) = 0.0010;
uniform float cool_shadow_amount : hint_range(0.0, 0.3, 0.01) = 0.15;
uniform float contrast : hint_range(0.8, 1.3, 0.01) = 1.07;
uniform float black_lift : hint_range(0.0, 0.08, 0.001) = 0.018;
uniform float interference_intensity : hint_range(0.0, 1.0, 0.01) = 0.0;


float random_noise(vec2 coordinate) {
	return fract(sin(dot(coordinate, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	float interference = smoothstep(0.0, 1.0, interference_intensity);
	float horizontal_wave = sin(SCREEN_UV.y * 52.0 + TIME * 3.1);
	float vertical_wave = sin(SCREEN_UV.x * 31.0 - TIME * 2.3);
	vec2 instability = vec2(horizontal_wave, vertical_wave) * 0.00115 * interference;
	float lens_breath = (
		0.0028 + sin(TIME * 2.15) * 0.0012
	) * interference;
	vec2 breathed_uv = (
		(SCREEN_UV - vec2(0.5)) * (1.0 - lens_breath) + vec2(0.5)
	);
	vec2 sample_uv = clamp(breathed_uv + instability, vec2(0.0), vec2(1.0));
	vec2 centered_uv = sample_uv * 2.0 - 1.0;
	float radius = length(centered_uv * vec2(0.84, 1.0));
	float edge_mask = smoothstep(0.3, 1.25, radius);
	float active_aberration = chromatic_aberration + interference * 0.0022;
	vec2 color_offset = centered_uv * active_aberration * edge_mask;
	vec2 red_uv = clamp(sample_uv + color_offset, vec2(0.0), vec2(1.0));
	vec2 blue_uv = clamp(sample_uv - color_offset, vec2(0.0), vec2(1.0));

	vec3 center_sample = textureLod(screen_texture, sample_uv, 0.0).rgb;
	vec3 color = vec3(
		textureLod(screen_texture, red_uv, 0.0).r,
		center_sample.g,
		textureLod(screen_texture, blue_uv, 0.0).b
	);

	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float shadow_weight = pow(1.0 - clamp(luminance, 0.0, 1.0), 2.0);
	vec3 petroleum_tint = vec3(-0.012, 0.018, 0.040);
	color += petroleum_tint * cool_shadow_amount * shadow_weight;
	color = (color - 0.5) * contrast + 0.5;
	color = max(color, vec3(0.0));
	color = color * (1.0 - black_lift) + vec3(black_lift * 0.42, black_lift * 0.62, black_lift);
	float alien_glow_pulse = 0.72 + sin(TIME * 3.65) * 0.28;
	color += vec3(0.004, 0.018, 0.013) * interference * alien_glow_pulse;

	float grain = random_noise(FRAGCOORD.xy + vec2(floor(TIME * 24.0), floor(TIME * 17.0)));
	float active_grain = grain_amount + interference * 0.050;
	grain = (grain - 0.5) * active_grain;
	float grain_visibility = mix(0.65, 0.25, smoothstep(0.1, 0.9, luminance));
	color += grain * grain_visibility;
	float exposure_flutter = (
		sin(TIME * 8.7) * 0.026
		+ sin(TIME * 3.4 + 1.7) * 0.014
	) * interference;
	float signal_line = sin(sample_uv.y * 460.0 + TIME * 18.0) * 0.005 * interference;
	color *= 1.0 + exposure_flutter + signal_line;

	float vignette = smoothstep(0.38, 1.22, radius);
	color *= 1.0 - vignette * (vignette_amount + interference * 0.050);

	COLOR = vec4(color, 1.0);
}
