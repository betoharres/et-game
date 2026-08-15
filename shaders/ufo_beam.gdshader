shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(0.02, 0.5, 0.72, 0.018);
uniform float emission_strength : hint_range(0.0, 3.0, 0.01) = 0.38;


void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft_side = smoothstep(0.02, 0.58, facing);
	ALBEDO = beam_color.rgb;
	EMISSION = beam_color.rgb * emission_strength;
	ALPHA = beam_color.a * soft_side;
}
