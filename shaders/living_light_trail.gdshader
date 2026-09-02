shader_type spatial;
render_mode blend_add, depth_draw_never, unshaded, cull_disabled;

// Custom material for the LivingLight Trail3D.
//
// Trail3D builds the ribbon with UV.x running along the length, UV.y across it
// (0 and 1 on the edges, 0.5 on the center line) and COLOR already carrying
// color * color_gradient, sampled from the head (ratio 0, on the creature) to
// the tail (ratio 1). When mesh_alignment is Billboard the side vertices are
// collapsed onto the center line and CUSTOM0 carries the tangent plus the half
// width, so the billboarding has to be redone here exactly like the built-in
// trail shaders do, otherwise the ribbon renders with no width at all.

uniform sampler2D flow_noise : hint_default_white, repeat_enable, filter_linear;
uniform float flow_speed = 0.75;
uniform float flow_tiling = 1.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.45;
uniform float edge_softness : hint_range(0.5, 6.0) = 2.1;
uniform float energy : hint_range(0.0, 4.0) = 1.0;
uniform vec4 flare_color : source_color = vec4(1.0, 0.95, 0.62, 1.0);

void vertex() {
	if (dot(CUSTOM0.xyz, CUSTOM0.xyz) > 0.0) {
		vec3 p = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		p = VERTEX - p;
		vec3 t = CUSTOM0.xyz;
		vec3 binormal = normalize(cross(p, t));
		vec3 normal = normalize(cross(t, binormal));
		vec3 tangent = normalize(cross(binormal, normal));
		VERTEX += CUSTOM0.w * binormal;
		NORMAL = normal;
		TANGENT = tangent;
		BINORMAL = binormal;
	}
}

void fragment() {
	// 0 on the center line of the ribbon, 1 on both edges.
	float across = abs(UV.y - 0.5) * 2.0;
	float body = pow(clamp(1.0 - across, 0.0, 1.0), edge_softness);

	// Energy running from the head towards the tail. UV.x is already scaled by
	// tiling_multiplier and anchored in place when pin_uv is on, so scrolling it
	// with TIME reads as light travelling inside the ribbon instead of the whole
	// texture sliding along with the creature.
	float flow = texture(flow_noise, vec2(UV.x * flow_tiling - TIME * flow_speed, UV.y * 0.5)).r;
	float pulse = mix(1.0, 0.35 + flow * 1.15, noise_strength);

	// The core of the ribbon burns towards the flare color, the edges keep the
	// gradient color, which is what sells the hot-center look of a firefly.
	vec3 hot = mix(COLOR.rgb, flare_color.rgb, body * body * 0.6);

	ALBEDO = hot * energy;
	ALPHA = COLOR.a * body * pulse;
}
