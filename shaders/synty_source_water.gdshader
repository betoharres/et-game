shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D scrolling_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D opacity_texture : filter_linear_mipmap, repeat_enable;
uniform bool opacity_enabled = false;
uniform vec4 water_color : source_color = vec4(0.08, 0.3, 0.36, 0.7);
uniform vec2 flow = vec2(0.025, 0.015);
uniform float foam_strength : hint_range(0.0, 1.0) = 0.08;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec2 moving_uv = UV + TIME * flow;
	vec3 n1 = texture(normal_texture, moving_uv).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_texture, UV * 1.7 - TIME * flow).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z)) * 0.5 + 0.5;
	float variation = texture(scrolling_texture, moving_uv).r * texture(noise_texture, UV * 2.0).r;
	float foam = smoothstep(0.6, 1.0, texture(foam_texture, moving_uv * 2.0).r) * foam_strength;
	ALBEDO = mix(water_color.rgb * (0.85 + 0.3 * variation), vec3(0.9), foam);
	ALPHA = water_color.a * (opacity_enabled ? texture(opacity_texture, moving_uv).r : 1.0);
	ROUGHNESS = roughness;
}
