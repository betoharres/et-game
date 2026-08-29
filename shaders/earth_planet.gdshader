shader_type spatial;

// Terra vista da orbita, gerada por ruido. Nada de textura: os PNGs de planeta
// do pacote Sci-Fi City sao sprites cinzas de disco, sem mapa esferico, entao a
// superficie e desenhada aqui.
//
// O ruido e amostrado em 3D a partir da direcao local do vertice, e nao pela UV
// da esfera: assim os continentes nao se espremem nos polos e as nuvens podem
// girar em torno do eixo sem esticar a costura da UV.
//
// A iluminacao normal do Godot resolve o terminador dia/noite. O uniform
// sun_direction (do planeta para o sol, em espaco global) so serve para saber
// que lado esta na sombra e acender ali as luzes das cidades.

uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

uniform vec3 ocean_deep : source_color = vec3(0.012, 0.055, 0.16);
uniform vec3 ocean_shallow : source_color = vec3(0.05, 0.25, 0.42);
uniform vec3 land_low : source_color = vec3(0.10, 0.26, 0.13);
uniform vec3 land_high : source_color = vec3(0.36, 0.31, 0.18);
uniform vec3 ice_color : source_color = vec3(0.82, 0.90, 0.96);
uniform vec3 cloud_color : source_color = vec3(0.92, 0.95, 1.0);
uniform vec3 city_light_color : source_color = vec3(1.0, 0.72, 0.36);

uniform float continent_scale : hint_range(0.5, 6.0, 0.1) = 2.1;
uniform float sea_level : hint_range(0.2, 0.8, 0.01) = 0.52;
uniform float ice_latitude : hint_range(0.4, 1.0, 0.01) = 0.74;
uniform float cloud_scale : hint_range(0.5, 8.0, 0.1) = 3.1;
uniform float cloud_coverage : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float cloud_opacity : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float cloud_speed : hint_range(0.0, 0.2, 0.001) = 0.012;
uniform float city_light_strength : hint_range(0.0, 4.0, 0.05) = 1.1;

varying vec3 local_direction;
varying vec3 world_normal;


float hash13(vec3 point) {
	point = fract(point * 0.1031);
	point += dot(point, point.yzx + 33.33);
	return fract((point.x + point.y) * point.z);
}


float value_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);

	float c000 = hash13(cell);
	float c100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float c010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float c110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float c001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float c101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float c011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float c111 = hash13(cell + vec3(1.0, 1.0, 1.0));

	return mix(
		mix(mix(c000, c100, local.x), mix(c010, c110, local.x), local.y),
		mix(mix(c001, c101, local.x), mix(c011, c111, local.x), local.y),
		local.z
	);
}


float fbm(vec3 point, int octaves) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int index = 0; index < octaves; index++) {
		total += value_noise(point) * amplitude;
		point *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}


vec3 rotate_y(vec3 point, float angle) {
	float sine = sin(angle);
	float cosine = cos(angle);
	return vec3(
		cosine * point.x + sine * point.z,
		point.y,
		-sine * point.x + cosine * point.z
	);
}


void vertex() {
	local_direction = normalize(VERTEX);
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec3 surface_point = local_direction * continent_scale;
	float elevation = fbm(surface_point, 5);
	// Segunda oitava lenta: sem ela os continentes ficam todos do mesmo tamanho.
	elevation = mix(elevation, fbm(surface_point * 0.43 + 11.7, 3), 0.35);

	float land = smoothstep(sea_level - 0.015, sea_level + 0.035, elevation);
	vec3 ocean = mix(
		ocean_deep,
		ocean_shallow,
		smoothstep(sea_level - 0.20, sea_level, elevation)
	);
	vec3 ground = mix(
		land_low,
		land_high,
		smoothstep(sea_level + 0.04, sea_level + 0.20, elevation)
	);
	vec3 surface = mix(ocean, ground, land);

	float latitude = abs(local_direction.y);
	float ice = smoothstep(
		ice_latitude,
		ice_latitude + 0.16,
		latitude + (elevation - sea_level) * 0.35
	);
	surface = mix(surface, ice_color, ice);

	vec3 cloud_point = rotate_y(local_direction, TIME * cloud_speed) * cloud_scale;
	float cloud_noise = fbm(cloud_point, 4);
	float clouds = smoothstep(cloud_coverage, cloud_coverage + 0.22, cloud_noise);
	// As nuvens rareiam sobre os polos, onde o ruido esferico se acumula.
	clouds *= 1.0 - smoothstep(0.86, 1.0, latitude);

	ALBEDO = mix(surface, cloud_color, clouds * cloud_opacity);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.28, 0.95, max(land, clouds));
	SPECULAR = mix(0.6, 0.12, max(land, clouds));

	float night = smoothstep(
		0.10,
		-0.25,
		dot(normalize(world_normal), normalize(sun_direction))
	);
	float city_mask = smoothstep(0.60, 0.74, fbm(local_direction * 16.0, 3));
	float cities = land * city_mask * (1.0 - clouds) * (1.0 - ice);
	EMISSION = city_light_color * cities * night * city_light_strength;
}
