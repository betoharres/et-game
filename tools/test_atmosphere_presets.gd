extends SceneTree

## Smoke test da nevoa rasteira e dos presets de atmosfera do NightEnvironment.
## Duas camadas ativas: a manta rente ao chao e o fog atmosferico em modo Depth,
## que fecha opaco antes do "far" das cameras. O volumetric fog fica desligado.

const MAX_LAYER_HEIGHT : float = 1.5

var _failed : bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var environment_node : Node = (
		load("res://scenes/NightEnvironment.tscn") as PackedScene
	).instantiate()
	root.add_child(environment_node)
	var camera : Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	await process_frame

	var world_environment : WorldEnvironment = environment_node.get_node(
		"WorldEnvironment"
	)
	var environment : Environment = world_environment.environment
	var fog_volume : FogVolume = environment_node.get_node("GroundFog")
	var fog_layer : Node3D = environment_node.get_node("GroundFogLayer")

	_check(
		environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH,
		"O fog atmosferico de tela cheia esta ligado em modo Depth"
	)
	_check(
		environment.fog_density >= 0.99,
		"fog_density fica em 1.0: em modo Depth ele multiplica a rampa"
	)
	_check(
		is_zero_approx(environment.fog_height_density),
		"fog_height_density fica em 0: ele tambem multiplicaria o depth fog"
	)
	_check(
		int(environment_node.call("get_quality_preset")) == 2,
		"Preset padrao da fase e HIGH"
	)
	_check(
		_max_layer_height(fog_layer) <= MAX_LAYER_HEIGHT,
		"As camadas de nevoa ficam rentes ao chao"
	)

	var previous_reach : float = 0.0
	for preset : int in [0, 1, 2]:
		environment_node.call("set_quality_preset", preset)
		await process_frame
		var label : String = ["LOW", "MEDIUM", "HIGH"][preset]
		_check(
			not environment.volumetric_fog_enabled,
			"%s nao liga o volumetric fog global" % label
		)
		_check(not fog_volume.visible, "%s nao usa o FogVolume" % label)
		_check(
			environment.fog_enabled and environment.fog_depth_end <= 400.0,
			"%s fecha o fog atmosferico dentro de 400 m" % label
		)
		_check(
			bool(fog_layer.call("is_fog_enabled")) and _visible_layers(fog_layer) >= 1,
			"%s mantem a nevoa rasteira" % label
		)
		var reach : float = float(_shader_value(fog_layer, "far_fade_end"))
		_check(reach > previous_reach, "%s amplia o alcance da nevoa" % label)
		previous_reach = reach

	_check(
		_visible_layers(fog_layer) == 2,
		"HIGH usa duas camadas de nevoa rasteira"
	)

	# O fog atmosferico pode ser desligado por quem quiser so a manta rasteira.
	environment_node.set("atmospheric_fog_enabled", false)
	environment_node.call("set_debug_fog_intensity", 1.0)
	await process_frame
	_check(
		not environment.fog_enabled,
		"atmospheric_fog_enabled desliga o fog de tela cheia"
	)
	environment_node.set("atmospheric_fog_enabled", true)
	environment_node.call("set_debug_fog_intensity", 1.0)
	await process_frame

	# Perfil de voo: mesma nevoa, so mais aberta, e volta sozinha ao pousar.
	var ground_end : float = environment.fog_depth_end
	environment_node.call("set_fog_profile", 1)
	await _settle_fog(environment)
	_check(
		environment.fog_depth_end > ground_end,
		"O perfil de voo afasta a parede de nevoa"
	)
	_check(
		environment.fog_depth_end <= 1000.0,
		"O perfil de voo fecha antes do plano distante da camera do aviao"
	)
	environment_node.call("set_fog_profile", 0)
	await _settle_fog(environment)
	_check(
		absf(environment.fog_depth_end - ground_end) <= 1.0,
		"Sair do aviao devolve o perfil de chao"
	)

	# Selecao de luzes: continua valendo se a volumetria for religada.
	var free_light : OmniLight3D = OmniLight3D.new()
	free_light.light_volumetric_fog_energy = 0.5
	root.add_child(free_light)
	var beam_light : SpotLight3D = SpotLight3D.new()
	beam_light.light_volumetric_fog_energy = 1.0
	beam_light.add_to_group("volumetric_lights")
	beam_light.add_to_group("alien_volumetric_lights")
	root.add_child(beam_light)
	environment_node.call("set_quality_preset", 1)
	await process_frame
	await process_frame
	_check(
		is_zero_approx(free_light.light_volumetric_fog_energy),
		"Luzes comuns saem da volumetria fora do preset HIGH"
	)
	_check(
		beam_light.light_volumetric_fog_energy > 0.0,
		"Luzes alienigenas continuam reservadas para a volumetria"
	)
	environment_node.call("set_quality_preset", 2)
	await process_frame
	await process_frame
	_check(
		is_equal_approx(free_light.light_volumetric_fog_energy, 0.5),
		"HIGH devolve a volumetria das luzes comuns"
	)

	# Evento alienigena: transicao suave, nao instantanea.
	environment_node.call("set_alien_fog_intensity", 1.0)
	await process_frame
	var first_step : float = float(environment_node.call("get_alien_fog_intensity"))
	_check(
		first_step > 0.0 and first_step < 0.9,
		"A atmosfera alienigena entra de forma gradual"
	)
	for _frame : int in 240:
		await process_frame
	_check(
		float(environment_node.call("get_alien_fog_intensity")) > 0.9,
		"A atmosfera alienigena atinge o alvo pedido"
	)
	_check(
		float(fog_layer.call("get_alien_blend")) > 0.9,
		"A nevoa rasteira acompanha o evento alienigena"
	)
	_check(
		float(_shader_value(fog_layer, "alien_blend")) > 0.9,
		"A nevoa rasteira ganha a tonalidade ciano-esverdeada"
	)
	_check(
		beam_light.light_volumetric_fog_energy > 1.0,
		"Os feixes ficam mais visiveis no ar durante o evento"
	)
	_check(
		not environment.volumetric_fog_enabled,
		"O evento alienigena nao reativa a volumetria sozinho"
	)

	# A suavidade ja foi verificada na entrada; acelera a resposta para que a
	# volta ao normal termine dentro de um numero previsivel de frames.
	environment_node.set("alien_fog_response", 8.0)
	environment_node.call("set_alien_fog_intensity", 0.0)
	for _frame : int in 600:
		await process_frame
	_check(
		is_zero_approx(float(environment_node.call("get_alien_fog_intensity"))),
		"A atmosfera volta ao normal ao encerrar o evento"
	)
	_check(
		is_zero_approx(float(_shader_value(fog_layer, "alien_blend"))),
		"A nevoa rasteira recupera a cor original"
	)

	# Zonas reutilizaveis nos campos.
	for scene_path : String in [
		"res://scenes/AnimatedCrops/WheatField.tscn",
		"res://scenes/AnimatedCrops/SunflowersPatch.tscn",
	]:
		var field : Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(field)
		var zone : Node = field.get_node_or_null("FogZone")
		_check(
			zone != null and zone.is_in_group("fog_zones"),
			"Zona de nevoa configurada em %s" % scene_path.get_file()
		)
		if zone != null:
			_check(
				float(zone.call("get_fog_strength")) > 0.0,
				"Zona de %s reforca a nevoa rasteira" % scene_path.get_file()
			)
		field.queue_free()

	print("ATMOSPHERE_PRESETS_TEST|%s" % ["FAIL" if _failed else "PASS"])
	quit(1 if _failed else 0)


func _fog_material(fog_layer : Node3D) -> ShaderMaterial:
	for child : Node in fog_layer.get_children():
		var layer : MeshInstance3D = child as MeshInstance3D
		if layer != null:
			return layer.get_active_material(0) as ShaderMaterial
	return null


func _shader_value(fog_layer : Node3D, parameter : StringName) -> float:
	var material : ShaderMaterial = _fog_material(fog_layer)
	if material == null:
		return 0.0
	var stored : Variant = material.get_shader_parameter(parameter)
	return 0.0 if stored == null else float(stored)


func _max_layer_height(fog_layer : Node3D) -> float:
	var highest : float = 0.0
	for child : Node in fog_layer.get_children():
		var layer : MeshInstance3D = child as MeshInstance3D
		if layer != null:
			highest = maxf(highest, layer.position.y)
	return highest


func _visible_layers(fog_layer : Node3D) -> int:
	var count : int = 0
	for child : Node in fog_layer.get_children():
		var layer : MeshInstance3D = child as MeshInstance3D
		if layer != null and layer.visible:
			count += 1
	return count


## Espera a transicao de perfil de nevoa estabilizar, com teto de frames.
func _settle_fog(environment : Environment) -> void:
	var previous : float = environment.fog_depth_end
	for i in 2000:
		await process_frame
		if absf(environment.fog_depth_end - previous) < 0.01:
			return
		previous = environment.fog_depth_end


func _check(condition : bool, label : String) -> void:
	print("CHECK|%s|%s" % ["PASS" if condition else "FAIL", label])
	_failed = _failed or not condition
