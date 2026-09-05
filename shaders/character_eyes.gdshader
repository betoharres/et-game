shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float eye_scale : hint_range(0.62, 1.38) = 1.0;
uniform vec4 eye_albedo : source_color = vec4(0.012, 0.018, 0.024, 1.0);
uniform vec4 eye_emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float eye_emission_energy : hint_range(0.0, 4.0) = 0.0;

void vertex() {
	// The source GLB keeps both eyes in their own surface. Scaling each island
	// around its bind-pose center makes them independent from head size while
	// the regular skinning stage still follows the animated head bone.
	float side = VERTEX.x < 0.0 ? -1.0 : 1.0;
	vec3 eye_center = vec3(side * 0.03594, 0.81931, 0.07926);
	VERTEX = eye_center + (VERTEX - eye_center) * eye_scale;
}

void fragment() {
	ALBEDO = eye_albedo.rgb;
	EMISSION = eye_emission.rgb * eye_emission_energy;
	METALLIC = 0.15;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
}
