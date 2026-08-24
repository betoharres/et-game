 shader_type spatial;

render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled;

uniform vec3 xray_center;
uniform float xray_radius = 30.0;
uniform float inner_radius = 12.0;

uniform float opacity = 0.65;

varying vec3 world_pos;

void vertex()
{
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment()
{
	float dist = distance(world_pos, xray_center);

	if (dist > xray_radius) {
		discard;
	}

	float f = dist / xray_radius;

	float inner_edge = inner_radius / xray_radius;
	vec3 col;

	if (f < inner_edge) {
		// FarSight: green at the centre, fading to red at inner_edge.
		float t = f / inner_edge;
		float green = sin((1.0 - t) * 1.5707963);
		col = vec3(1.0 - green, green, 0.0);
	} else {
		// The outer band keeps red and adds blue toward the radius.
		float t = (f - inner_edge) / (1.0 - inner_edge);
		float blue = sin((t * 0.65 + 0.35) * 1.5707963);
		col = vec3(1.0, 0.0, blue);
	}

	// FarSight fades from 25% of the radius to the outer boundary.
	float edge = 1.0 - clamp((f - 0.25) / 0.75, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = opacity * edge;
}
