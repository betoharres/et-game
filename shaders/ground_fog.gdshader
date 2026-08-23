shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Nevoa rasteira "fake": planos horizontais que seguem a camera e recebem
// ruido procedural animado em espaco de mundo. Substitui volumetria cara
// perto do chao mantendo o custo em fill-rate previsivel.
// Fade proximo/distante, fade por altura da camera, soft depth contra o
// cenario e reforco por zonas (milharais, estradas, campos abertos).

const int MAX_FOG_ZONES = 6;

group_uniforms Look;
uniform vec3 fog_color : source_color = vec3(0.09, 0.17, 0.23);
uniform vec3 alien_color : source_color = vec3(0.09, 0.6, 0.5);
uniform float alien_blend : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float alien_glow : hint_range(1.0, 4.0, 0.01) = 1.7;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.42;

group_uniforms Shape;
uniform float noise_scale : hint_range(0.002, 0.2, 0.001) = 0.024;
uniform float coverage : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float softness : hint_range(0.05, 1.0, 0.01) = 0.46;
uniform float detail_amount : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float warp_amount : hint_range(0.0, 3.0, 0.01) = 1.15;

group_uniforms Motion;
uniform vec2 drift_direction = vec2(0.82, 0.34);
uniform float drift_speed : hint_range(0.0, 2.0, 0.01) = 0.11;
uniform float swell_speed : hint_range(0.0, 1.0, 0.01) = 0.06;

group_uniforms Fading;
uniform float near_fade : hint_range(0.0, 30.0, 0.1) = 3.4;
uniform float far_fade_start : hint_range(0.0, 300.0, 1.0) = 58.0;
uniform float far_fade_end : hint_range(1.0, 400.0, 1.0) = 98.0;
uniform float height_fade_start : hint_range(0.0, 80.0, 0.5) = 9.0;
uniform float height_fade_end : hint_range(1.0, 200.0, 0.5) = 28.0;
uniform float soft_depth : hint_range(0.0, 20.0, 0.1) = 3.0;
// A camada e um plano: perto do seu horizonte o fade por distancia comprime em
// poucos pixels e vira uma linha reta. Este fade usa a inclinacao do raio de
// visao, que e proporcional a altura na tela, entao o degrade fica uniforme.
uniform float horizon_fade : hint_range(0.005, 0.4, 0.001) = 0.045;
// Separacao minima considerada, para a nevoa nao sumir com a camera dentro dela.
uniform float horizon_min_height : hint_range(0.1, 12.0, 0.1) = 2.0;

group_uniforms Zones;
uniform int fog_zone_count : hint_range(0, 6) = 0;
// Empacotado como (x, z, raio, reforco) por zona.
uniform float fog_zone_data[24];

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

instance uniform float layer_seed = 0.0;
instance uniform float layer_opacity = 1.0;
instance uniform float layer_scale = 1.0;

varying vec3 world_position;
varying float swell;


float hash21(vec2 point) {
	vec3 point3 = fract(vec3(point.xyx) * 0.1031);
	point3 += dot(point3, point3.yzx + 33.33);
	return fract((point3.x + point3.y) * point3.z);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


float fog_noise(vec2 point) {
	float result = value_noise(point) * 0.6;
	result += value_noise(point * 2.13 + vec2(3.7, 1.4)) * 0.27;
	float weight = 0.87;
	if (detail_amount > 0.001) {
		result += value_noise(point * 4.31 + vec2(7.1, 9.3)) * 0.13 * detail_amount;
		weight += 0.13 * detail_amount;
	}
	return result / weight;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	swell = sin(TIME * swell_speed + layer_seed * 2.4) * 0.045;
}


void fragment() {
	vec3 camera_position = CAMERA_POSITION_WORLD;

	float ground_distance = length(world_position.xz - camera_position.xz);
	float near_mask = smoothstep(0.0, max(near_fade, 0.01), ground_distance);
	float far_mask = 1.0 - smoothstep(
		far_fade_start,
		max(far_fade_end, far_fade_start + 1.0),
		ground_distance
	);
	vec2 edge_uv = min(UV, vec2(1.0) - UV);
	float edge_mask = smoothstep(0.0, 0.04, min(edge_uv.x, edge_uv.y));

	float camera_height = camera_position.y - world_position.y;
	float grazing = max(abs(camera_height), horizon_min_height) / max(
		ground_distance,
		0.001
	);
	float horizon_mask = smoothstep(0.0, max(horizon_fade, 0.001), grazing);

	float distance_mask = near_mask * far_mask * edge_mask * horizon_mask;
	if (distance_mask <= 0.006) {
		discard;
	}

	float height_mask = 1.0 - smoothstep(
		height_fade_start,
		max(height_fade_end, height_fade_start + 1.0),
		camera_height
	);
	if (height_mask <= 0.006) {
		discard;
	}

	vec2 sample_point = world_position.xz * (noise_scale * layer_scale);
	sample_point += vec2(layer_seed * 37.0, layer_seed * -21.0);
	sample_point += drift_direction * TIME * drift_speed;
	if (warp_amount > 0.001) {
		vec2 warp = vec2(
			value_noise(sample_point * 0.55 + vec2(1.7, 8.2)),
			value_noise(sample_point * 0.55 + vec2(5.3, 2.9))
		) - 0.5;
		sample_point += warp * warp_amount;
	}

	float density = fog_noise(sample_point) + swell;

	float zone_boost = 0.0;
	for (int index = 0; index < fog_zone_count; index++) {
		int offset = index * 4;
		vec2 zone_center = vec2(fog_zone_data[offset], fog_zone_data[offset + 1]);
		float zone_radius = max(fog_zone_data[offset + 2], 0.5);
		float zone_distance = length(world_position.xz - zone_center);
		float falloff = 1.0 - smoothstep(zone_radius * 0.3, zone_radius, zone_distance);
		zone_boost = max(zone_boost, fog_zone_data[offset + 3] * falloff);
	}

	float threshold = mix(0.78, 0.16, clamp(coverage + zone_boost * 0.35, 0.0, 1.0));
	density = smoothstep(threshold - softness * 0.5, threshold + softness * 0.5, density);
	density *= 1.0 + zone_boost * 0.4;

	float alpha = opacity * layer_opacity * density * distance_mask * height_mask;

	if (soft_depth > 0.001) {
		float raw_depth = texture(depth_texture, SCREEN_UV).x;
		vec4 view_position = INV_PROJECTION_MATRIX * vec4(
			vec3(SCREEN_UV * 2.0 - 1.0, raw_depth),
			1.0
		);
		view_position.xyz /= view_position.w;
		float scene_depth = -view_position.z;
		float surface_depth = -VERTEX.z;
		alpha *= clamp((scene_depth - surface_depth) / soft_depth, 0.0, 1.0);
	}

	if (alpha < 0.004) {
		discard;
	}

	vec3 color = mix(fog_color, alien_color * alien_glow, alien_blend * 0.75);
	color *= mix(0.84, 1.16, density);
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
