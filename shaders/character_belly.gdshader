shader_type spatial;
// The source skin is double-sided. Keeping the procedural belly double-sided
// as well prevents its inside from looking transparent where it intersects
// the animated torso, while the lack of ALPHA keeps it in the opaque pass.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 skin_albedo : source_color = vec4(0.68, 0.68, 0.68, 1.0);
uniform float fat_amount : hint_range(0.0, 1.0) = 0.0;

varying float belly_y;
varying float belly_front;

void vertex() {
	belly_y = VERTEX.y;
	belly_front = smoothstep(0.08, 0.72, VERTEX.z);
}

void fragment() {
	float fold_one = exp(-pow((belly_y + 0.08) / 0.055, 2.0));
	float fold_two = exp(-pow((belly_y - 0.22) / 0.065, 2.0));
	float second_fold_weight = smoothstep(0.44, 0.82, fat_amount);
	float folds = (fold_one + fold_two * second_fold_weight)
		* belly_front * fat_amount;
	ALBEDO = skin_albedo.rgb * (1.0 - folds * 0.055);
	ROUGHNESS = clamp(0.72 + folds * 0.12, 0.0, 1.0);
	SPECULAR = 0.32;
}
