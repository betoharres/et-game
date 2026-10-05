shader_type spatial;
render_mode cull_disabled;

uniform sampler2D texture_albedo_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo_b : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D trunk_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool leaf_normal_enabled = false;
uniform bool trunk_normal_enabled = false;
uniform vec4 albedo_a : source_color = vec4(1.0);
uniform vec4 albedo_b : source_color = vec4(1.0);
uniform float blend_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	float leaves_mask = step(blend_threshold, COLOR.b);
	vec4 leaves = texture(texture_albedo_a, UV) * albedo_a;
	vec4 trunk = texture(texture_albedo_b, UV) * albedo_b;
	vec4 surface = mix(trunk, leaves, leaves_mask);
	ALBEDO = surface.rgb;
	ALPHA = surface.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	vec3 leaves_n = leaf_normal_enabled ? texture(leaf_normal, UV).rgb : vec3(0.5, 0.5, 1.0);
	vec3 trunk_n = trunk_normal_enabled ? texture(trunk_normal, UV).rgb : vec3(0.5, 0.5, 1.0);
	NORMAL_MAP = mix(trunk_n, leaves_n, leaves_mask);
}
