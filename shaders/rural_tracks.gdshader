shader_type spatial;
// Decalque de chao: nao escreve profundidade e dissolve na borda, entao a fita
// nao cria emenda com o terreno que aparece por baixo dela.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;

uniform sampler2D soil_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// O mesmo tom de terra do material do terreno: a marca escurece a partir dele.
uniform vec3 soil_color : source_color = vec3(0.46, 0.39, 0.29);
uniform vec3 rut_color : source_color = vec3(0.33, 0.27, 0.20);
uniform float soil_scale : hint_range(0.05, 0.6) = 0.24;
varying vec3 world_position;
varying float band_cover;
varying float band_wear;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	band_cover = COLOR.a;
	band_wear = COLOR.r;
}

void fragment() {
	vec2 p = world_position.xz;
	float variation = sin(p.x * 0.37 + sin(p.y * 0.31)) * sin(p.y * 0.23 + 0.7);
	float wear = clamp(band_wear * (0.9 + variation * 0.1), 0.0, 1.0);
	vec3 detail = texture(soil_texture, p * soil_scale).rgb;
	float luma = clamp(dot(detail, vec3(0.2126, 0.7152, 0.0722)) / 0.10168, 0.6, 1.6);
	float distance_fade = smoothstep(30.0, 150.0, distance(world_position, CAMERA_POSITION_WORLD));
	ALBEDO = mix(soil_color, rut_color, wear) * mix(1.0, luma, mix(0.6, 0.15, distance_fade));
	// Borda transparente: a terra pisada apaga aos poucos sobre o pasto.
	ALPHA = clamp(band_cover * (0.45 + 0.55 * wear), 0.0, 1.0);
	vec4 pbr = texture(soil_normal, p * soil_scale);
	NORMAL_MAP = pbr.rgb;
	NORMAL_MAP_DEPTH = 0.55 * (1.0 - distance_fade * 0.7);
	ROUGHNESS = pbr.a;
	SPECULAR = 0.08;
}
