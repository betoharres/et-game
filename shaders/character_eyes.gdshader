shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 eye_albedo : source_color = vec4(0.012, 0.018, 0.024, 1.0);
uniform vec4 eye_emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float eye_emission_energy : hint_range(0.0, 4.0) = 0.0;

void fragment() {
	ALBEDO = eye_albedo.rgb;
	EMISSION = eye_emission.rgb * eye_emission_energy;
	METALLIC = 0.15;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
}
