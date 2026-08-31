shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

uniform vec4 glass_color : source_color = vec4(0.05, 0.46, 0.58, 0.24);
uniform vec3 edge_color = vec3(0.06, 0.7, 0.76);
uniform float inner_radius = 5.25;

varying vec3 local_position;


void vertex() {
	local_position = VERTEX;
}


void fragment() {
	if (length(local_position.xz) < inner_radius) {
		discard;
	}

	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
	ALBEDO = glass_color.rgb;
	ALPHA = mix(glass_color.a, 0.58, fresnel);
	METALLIC = 0.16;
	ROUGHNESS = 0.08;
	EMISSION = edge_color * (0.08 + fresnel * 0.22);
}
