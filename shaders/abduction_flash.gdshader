shader_type canvas_item;

// Transition used when the player is pulled out of the menu and into the fase.
// Deliberately avoids any clean geometric shape (no circle, no rectangle, no
// linear wipe): the screen is swallowed by an energy front that climbs from the
// bottom with jittering scanlines, blows out to white, then burns off.

uniform float progress : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float dissipate : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform vec4 beam_color : source_color = vec4(0.55, 0.92, 1.0, 1.0);

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(41.317, 289.113))) * 43758.5453);
}

void fragment() {
	float charge = clamp(progress, 0.0, 1.0);

	// Distance from the bottom of the screen: the front travels upward.
	float height = 1.0 - UV.y;

	// Per-scanline jitter so the leading edge reads as unstable energy rather
	// than a drawn line. Quantized in time so it strobes instead of sliding.
	float scanline = floor(UV.y * 190.0);
	float strobe = floor(TIME * 26.0);
	float jitter = (hash(vec2(scanline, strobe)) - 0.5) * 0.11;

	float edge = 1.0 - charge * 1.18 + jitter * charge;
	float coverage = smoothstep(edge, edge + 0.13, height);

	// Hot band riding the front of the wave.
	float band = smoothstep(0.0, 0.3, coverage) * (1.0 - smoothstep(0.05, 0.5, coverage));

	// Horizontal tearing inside the covered area.
	float tear = hash(vec2(scanline, strobe + 7.0));
	coverage *= 1.0 - step(0.965, tear) * 0.55 * (1.0 - charge);

	// Once fully charged the front is irrelevant: the frame is blown out.
	float sweep_alpha = max(coverage, smoothstep(0.72, 1.0, charge));

	// Burn-off phase: uniform sheet decaying with residual scanline noise.
	float residue = 1.0 - step(0.5, hash(vec2(scanline, strobe + 3.0))) * 0.35;
	float burn_alpha = charge * mix(1.0, residue, 0.35 * (1.0 - charge));

	float alpha = mix(sweep_alpha, burn_alpha, dissipate);
	vec3 color = mix(beam_color.rgb, vec3(1.0), clamp(charge * charge + band, 0.0, 1.0));

	COLOR = vec4(color, alpha);
}
