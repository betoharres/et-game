shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 skin_albedo : source_color = vec4(0.68, 0.68, 0.68, 1.0);
void fragment() {
	ALBEDO = skin_albedo.rgb;
	ROUGHNESS = 0.72;
	SPECULAR = 0.32;
}
