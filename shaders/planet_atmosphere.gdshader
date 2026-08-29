shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled, cull_back;

// Casca fina sobre o planeta: so a borda acende (fresnel) e so no lado voltado
// para o sol, de modo que o terminador da Terra continua legivel. Aditiva e sem
// escrita de profundidade para nao recortar a superficie por baixo.

uniform vec3 atmosphere_color : source_color = vec3(0.28, 0.55, 1.0);
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.6;
uniform float intensity : hint_range(0.0, 4.0, 0.05) = 1.15;
uniform float night_intensity : hint_range(0.0, 1.0, 0.01) = 0.18;

varying vec3 world_normal;


void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power);
	float sun_facing = clamp(
		dot(normalize(world_normal), normalize(sun_direction)) * 0.5 + 0.5,
		0.0,
		1.0
	);
	float lit = mix(night_intensity, 1.0, smoothstep(0.35, 0.85, sun_facing));
	ALBEDO = atmosphere_color * intensity;
	ALPHA = clamp(rim * lit, 0.0, 1.0);
}
