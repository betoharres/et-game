shader_type canvas_item;

uniform vec2 center = vec2(0.5, 0.38);
uniform float radius : hint_range(0.0, 1.6, 0.01) = 1.5;
uniform float edge_softness : hint_range(0.0, 0.3, 0.01) = 0.07;
uniform vec4 wipe_color : source_color = vec4(0.55, 0.92, 1.0, 1.0);

void fragment() {
	vec2 aspect_ratio = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 delta = (UV - center) * aspect_ratio;
	float distance_from_center = length(delta);
	float mask = smoothstep(radius - edge_softness, radius + edge_softness, distance_from_center);
	COLOR = vec4(wipe_color.rgb, mask);
}
