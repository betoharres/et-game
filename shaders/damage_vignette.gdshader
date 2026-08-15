shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0, 0.01) = 0.0;


void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float edge = smoothstep(0.34, 1.15, length(centered_uv));
	COLOR = vec4(0.52, 0.015, 0.025, edge * intensity);
}
