@tool
extends SceneTree

func _process(_delta: float) -> bool:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	for prop: String in ["shadow_bias", "shadow_normal_bias", "shadow_blur",
			"directional_shadow_mode", "directional_shadow_split_1",
			"directional_shadow_split_2", "directional_shadow_split_3",
			"directional_shadow_max_distance", "directional_shadow_pancake_size",
			"shadow_transmittance_bias"]:
		print("%s = %s" % [prop, str(light.get(prop))])
	light.free()
	print("--- project shadow settings (defaults if absent) ---")
	for key: String in ["rendering/lights_and_shadows/directional_shadow/size",
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality"]:
		print("%s = %s" % [key, ProjectSettings.get_setting(key, "N/A (default)")])
	quit(0)
	return true
