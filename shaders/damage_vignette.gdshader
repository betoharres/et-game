shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float impact_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec2 hit_direction = vec2(0.0);
uniform vec4 damage_color : source_color = vec4(0.68, 0.025, 0.06, 1.0);
uniform float chromatic_pixels : hint_range(0.0, 6.0, 0.1) = 2.5;


void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float edge = smoothstep(0.3, 1.2, radius);
	vec2 radial_direction = centered_uv / max(radius, 0.001);
	float hit_side = max(dot(radial_direction, hit_direction), 0.0);
	float directional_edge = edge * mix(0.7, 1.0, hit_side);

	vec2 split = centered_uv * SCREEN_PIXEL_SIZE * chromatic_pixels * impact_strength * edge;
	vec3 screen = texture(screen_texture, SCREEN_UV).rgb;
	screen.r = texture(screen_texture, clamp(SCREEN_UV + split, vec2(0.0), vec2(1.0))).r;
	screen.b = texture(screen_texture, clamp(SCREEN_UV - split, vec2(0.0), vec2(1.0))).b;
	float luminance = dot(screen, vec3(0.2126, 0.7152, 0.0722));
	screen = mix(screen, vec3(luminance), impact_strength * 0.2);
	float flash = impact_strength * 0.055;
	float tint = clamp(directional_edge * intensity * 0.8 + flash, 0.0, 0.85);
	COLOR = vec4(mix(screen, damage_color.rgb, tint), 1.0);
}
