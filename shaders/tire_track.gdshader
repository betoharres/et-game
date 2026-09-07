shader_type spatial;
// Marca de pneu: fita fina colada no chao. Nao escreve profundidade e desenha
// depois do terreno, entao a fita nunca briga por z com o piso que fica embaixo.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, shadows_disabled;

uniform sampler2D tread_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Tom da terra revirada; combina com o rut_color das vias rurais.
uniform vec3 track_color : source_color = vec3(0.31, 0.25, 0.19);
uniform float opacity : hint_range(0.0, 1.0, 0.02) = 0.85;
// Granulacao em coordenadas de mundo: duas passagens paralelas nao ficam iguais.
uniform float grain_scale : hint_range(0.05, 2.0, 0.05) = 0.45;
uniform float grain_amount : hint_range(0.0, 0.6, 0.02) = 0.28;
uniform float fade_start : hint_range(10.0, 200.0, 5.0) = 70.0;
uniform float fade_end : hint_range(20.0, 400.0, 5.0) = 160.0;
uniform float roughness_value : hint_range(0.0, 1.0, 0.05) = 0.95;

varying vec3 world_position;
// COLOR.r guarda a intensidade da passagem, COLOR.a a cobertura da fita.
varying float wear;
varying float cover;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wear = COLOR.r;
	cover = COLOR.a;
}

void fragment() {
	vec4 tread = texture(tread_texture, UV);
	vec2 p = world_position.xz * grain_scale;
	float grain = sin(p.x * 1.7 + sin(p.y * 1.3)) * sin(p.y * 0.9 + 2.1);
	float distance_fade = 1.0 - smoothstep(fade_start, fade_end, distance(world_position, CAMERA_POSITION_WORLD));
	float mask = tread.a * cover * wear * opacity;
	mask *= 1.0 + grain * grain_amount;
	ALBEDO = track_color * mix(0.85, 1.15, tread.r) * (1.0 + grain * 0.08);
	ALPHA = clamp(mask, 0.0, 1.0) * distance_fade;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.05;
}
