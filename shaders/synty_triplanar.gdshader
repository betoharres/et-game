shader_type spatial;

uniform sampler2D _MainTex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D _AngledTex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bottom_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D _MainNormalTex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D _AngledNormalTex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D bottom_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float _Angle : hint_range(0.0, 90.0) = 45.0;
uniform float _Transition : hint_range(0.001, 0.5) = 0.2;
uniform vec3 triplanar_scale = vec3(1.0);
uniform vec3 triplanar_offset = vec3(0.0);
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

varying vec3 object_position;
varying vec3 object_normal;
varying mat3 normal_to_view;

vec3 sample_color(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
}

vec3 sample_normal(sampler2D tex, vec3 p, vec3 w, vec3 n) {
	vec3 x = texture(tex, p.zy).rgb * 2.0 - 1.0;
	vec3 y = texture(tex, p.xz).rgb * 2.0 - 1.0;
	vec3 z = texture(tex, p.xy).rgb * 2.0 - 1.0;
	// Neutral normal maps must preserve the mesh normal on every projection.
	vec3 nx = vec3(n.x * x.z, n.y + x.y, n.z + x.x);
	vec3 ny = vec3(n.x + y.x, n.y * y.z, n.z + y.y);
	vec3 nz = vec3(n.x + z.x, n.y + z.y, n.z * z.z);
	return normalize(nx * w.x + ny * w.y + nz * w.z);
}

void vertex() {
	object_position = VERTEX * triplanar_scale + triplanar_offset;
	object_normal = NORMAL;
	normal_to_view = MODELVIEW_NORMAL_MATRIX;
}

void fragment() {
	vec3 n = normalize(object_normal);
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	w /= max(dot(w, vec3(1.0)), 0.0001);
	float threshold = cos(radians(_Angle));
	float top = smoothstep(threshold - _Transition, threshold + _Transition, n.y);
	float bottom = smoothstep(threshold - _Transition, threshold + _Transition, -n.y);
	vec3 side_color = sample_color(_AngledTex, object_position, w);
	vec3 color = mix(side_color, sample_color(_MainTex, object_position, w), top);
	ALBEDO = mix(color, sample_color(bottom_texture, object_position, w), bottom);
	vec3 mapped = mix(sample_normal(_AngledNormalTex, object_position, w, n), sample_normal(_MainNormalTex, object_position, w, n), top);
	mapped = mix(mapped, sample_normal(bottom_normal, object_position, w, n), bottom);
	// Triplanar normals are in object space, rather than a UV tangent basis.
	NORMAL = normalize(normal_to_view * mapped);
	ROUGHNESS = 1.0;
}
