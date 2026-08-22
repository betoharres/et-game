shader_type spatial;

render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.03, 0.25, 0.32, 0.75);

uniform float wave_height = 0.12;
uniform float wave_scale = 1.5;
uniform float wave_speed = 0.8;

uniform float small_wave_height = 0.035;
uniform float small_wave_scale = 4.0;
uniform float small_wave_speed = 1.2;

uniform float roughness = 0.15;
uniform float metallic = 0.0;

uniform float fresnel_strength = 0.65;
uniform float fresnel_power = 4.0;


float wave(vec2 p, float scale, float speed, float time_offset)
{
	float w1 = sin(p.x * scale + TIME * speed + time_offset);
	float w2 = sin(p.y * scale * 1.37 + TIME * speed * 0.73);
	float w3 = sin((p.x + p.y) * scale * 0.71 + TIME * speed * 1.31);

	return (w1 + w2 + w3) / 3.0;
}


void vertex()
{
	vec2 p = VERTEX.xz * wave_scale;

	float large_wave = wave(
		p,
		1.0,
		wave_speed,
		0.0
	);

	float small_wave = wave(
		VERTEX.xz * small_wave_scale,
		1.0,
		small_wave_speed,
		2.7
	);

	VERTEX.y +=
		large_wave * wave_height +
		small_wave * small_wave_height;
}


void fragment()
{
	vec3 view_dir = normalize(VIEW);

	float fresnel = pow(
		1.0 - max(dot(NORMAL, view_dir), 0.0),
		fresnel_power
	);

	fresnel *= fresnel_strength;

	vec3 color = water_color.rgb;
	color += vec3(fresnel);

	ALBEDO = color;
	ALPHA = water_color.a;

	ROUGHNESS = roughness;
	METALLIC = metallic;
}