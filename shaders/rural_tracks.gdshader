shader_type spatial;
render_mode cull_disabled;

uniform sampler2D soil_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 soil_color : source_color = vec3(0.46, 0.39, 0.29);
uniform vec3 grass_color : source_color = vec3(0.42, 0.46, 0.31);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float variation = sin(p.x * 0.37 + sin(p.y * 0.31)) * sin(p.y * 0.23 + 0.7);
	float wear = clamp(COLOR.r * (0.88 + variation * 0.12), 0.0, 1.0);
	float distance_fade = smoothstep(25.0, 160.0, distance(world_position, CAMERA_POSITION_WORLD));
	vec3 soil = texture(soil_texture, p * 0.24).rgb;
	vec3 grass = texture(grass_texture, p * 0.325).rgb;
	float soil_detail = clamp(dot(soil, vec3(0.2126, 0.7152, 0.0722)) / 0.10168, 0.55, 1.65);
	float grass_detail = clamp(dot(grass, vec3(0.2126, 0.7152, 0.0722)) / 0.33391, 0.55, 1.65);
	soil = soil_color * mix(1.0, soil_detail, mix(0.72, 0.12, distance_fade));
	grass = grass_color * mix(1.0, grass_detail, mix(0.72, 0.12, distance_fade));
	// A little dry soil among the grass joins the surrounding meadow palette.
	ALBEDO = mix(mix(grass, soil, 0.12), soil * (0.94 + variation * 0.04), wear);
	vec4 grass_pbr = texture(grass_normal, p * 0.325);
	vec4 soil_pbr = texture(soil_normal, p * 0.24);
	NORMAL_MAP = mix(grass_pbr.rgb, soil_pbr.rgb, wear);
	NORMAL_MAP_DEPTH = 0.4 * (1.0 - distance_fade * 0.7);
	ROUGHNESS = mix(grass_pbr.a, soil_pbr.a, wear);
	SPECULAR = 0.1;
}
