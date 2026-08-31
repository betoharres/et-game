shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D metallic_roughness_texture : hint_default_white;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D emission_texture : source_color, hint_default_black;
uniform bool use_normal = false;
uniform bool use_emission = false;
uniform float emission_multiplier = 1.0;
uniform float inner_radius = 5.25;
uniform float outer_radius = 10.0;

varying vec3 local_position;
varying vec3 local_normal;


void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}


void fragment() {
	float radius = length(local_position.xz);
	bool interior_floor = local_normal.y > 0.9 && local_position.y < 1.1;
	bool exterior_floor = local_normal.y < -0.9 && local_position.y < 0.15;
	if (
		(interior_floor || exterior_floor)
		&& radius > inner_radius
		&& radius < outer_radius
	) {
		discard;
	}

	vec4 base_color = texture(albedo_texture, UV);
	vec4 metallic_roughness = texture(metallic_roughness_texture, UV);
	ALBEDO = base_color.rgb;
	METALLIC = metallic_roughness.r;
	ROUGHNESS = max(metallic_roughness.a, 0.08);

	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
	if (use_emission) {
		EMISSION = texture(emission_texture, UV).rgb * emission_multiplier;
	}
}
