shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 skin_albedo : source_color = vec4(0.68, 0.68, 0.68, 1.0);
uniform float fat_amount : hint_range(0.0, 1.0) = 0.0;

varying float abdomen_mask;
varying float abdomen_y;

void vertex() {
	// The GLB has too little abdominal topology for safe silhouette extrusion.
	// Keep this shader to subtle fold shading and let the procedural dome owned
	// by CharacterProportions create the rounded silhouette.
	float vertical_mask = smoothstep(0.29, 0.38, VERTEX.y)
		* (1.0 - smoothstep(0.60, 0.69, VERTEX.y));
	float center_mask = 1.0 - smoothstep(0.045, 0.092, abs(VERTEX.x));
	float front_mask = smoothstep(-0.018, 0.032, VERTEX.z);
	float belly_mask = vertical_mask * center_mask * front_mask;

	abdomen_mask = belly_mask;
	abdomen_y = VERTEX.y;
}

void fragment() {
	// Two shallow horizontal shadows suggest compressed folds without risking
	// unstable normal displacement on an animated, low-poly skinned mesh.
	float fold_one = exp(-pow((abdomen_y - 0.455) / 0.010, 2.0));
	float fold_two = exp(-pow((abdomen_y - 0.515) / 0.012, 2.0));
	float second_fold_weight = smoothstep(0.48, 0.82, fat_amount);
	float folds = (fold_one + fold_two * second_fold_weight)
		* abdomen_mask * fat_amount;
	float lower_highlight = exp(-pow((abdomen_y - 0.438) / 0.016, 2.0))
		* abdomen_mask * fat_amount;

	ALBEDO = skin_albedo.rgb * (1.0 - folds * 0.075);
	ALBEDO += skin_albedo.rgb * lower_highlight * 0.025;
	ROUGHNESS = clamp(0.72 + folds * 0.12, 0.0, 1.0);
	SPECULAR = 0.32;
}
