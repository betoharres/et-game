shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 liquid_color : source_color = vec4(0.08, 0.55, 0.25, 0.28);
uniform float bubble_speed = 0.18;

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 flow = vec2(UV.x * 20.0, UV.y * 12.0 - TIME * bubble_speed * 12.0);
	vec2 cell = floor(flow);
	vec2 center = vec2(0.25 + hash(cell) * 0.5, 0.25 + hash(cell + 4.0) * 0.5);
	float radius = mix(0.04, 0.13, hash(cell + 9.0));
	float distance_to_center = length(fract(flow) - center);
	float bubble = 1.0 - smoothstep(radius - 0.025, radius, distance_to_center);
	float rim = bubble * smoothstep(radius * 0.45, radius * 0.8, distance_to_center);
	float ripple = sin(UV.y * 32.0 + TIME * 1.4 + sin(UV.x * 18.0)) * 0.025;
	ALBEDO = liquid_color.rgb + vec3(ripple) + vec3(0.35, 0.6, 0.4) * rim;
	EMISSION = liquid_color.rgb * 0.18 + vec3(0.12, 0.35, 0.16) * rim;
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
	ALPHA = clamp(liquid_color.a + bubble * 0.28, 0.0, 0.7);
}
